open Ppatteries

module BA = Bigarray
module BA1 = BA.Array1
module BA2 = BA.Array2

let bases = "ACGT"

let informative = function
  | 'A' | 'C' | 'G' | 'T' -> true
  | _ -> false

let word_uninformative s =
  String.enum s |> Enum.for_all informative |> not

exception Invalid_base of char

(* get an index of a base *)
let base_idx base =
  try
    String.of_char base |> String.find bases
  with Not_found -> raise (Invalid_base base)

(* convert from a word to an int. Successive base indices are packed into the
 * integer using left shifts. *)
let word_to_int =
  String.fold_left
    (fun accum c -> base_idx c |> (lor) (accum lsl 2))
    0

(* convert from an int to a word, with optional padding *)
let int_to_word ?word_length i =
  Enum.unfold
    i
    (function 0 -> None | x -> Some (bases.[x land 3], x lsr 2))
  |> (match word_length with
       | None -> identity
       | Some l -> flip Enum.append (Enum.repeat bases.[0]) |- Enum.take l)
  |> String.of_backwards

(* the max word length is (log_4 max_int) - 1 *)
let max_word_length =
  log (float_of_int max_int) /. log 4. |> int_of_float |> pred

(* generalized count something by words in a sequence. generalized because we
 * are able to specify a modify function specifying action. *)
let gen_count_by_seq word_length modify seq =
  0 -- (String.length seq - word_length)
  |> Enum.map (flip (String.sub seq) word_length)
  |> Enum.iter (junction word_uninformative (const ()) (word_to_int |- modify))

(* the thing that accumulates reference sequences before classification *)
module Preclassifier = struct
  type base = {
    word_length: int;
    n_words: int;
    tax_ids: Tax_id.t array;
  }
  type 'a t = {
    base: base;
    freq_table: (int, 'a, BA.c_layout) BA2.t;
    taxid_counts: int array;
    seq_count: int ref;
  }

  exception Tax_id_not_found of Tax_id.t

  (* make a preclassifier, given kind, word_length, and tax_ids *)
  let make kind word_length tax_ids =
    if word_length > max_word_length then
      failwith
        (Printf.sprintf "max_word_length is %d (given word_length %d)"
           max_word_length word_length);
    let n_words = 1 lsl (word_length * 2)
    and n_taxids = Array.length tax_ids in
    let freq_table = BA2.create kind BA.c_layout n_taxids n_words
    and taxid_counts = Array.make n_taxids 0
    and seq_count = ref 0 in
    BA2.fill freq_table 0;
    {base = {word_length; n_words; tax_ids}; taxid_counts; freq_table; seq_count}

  (* find the index of a tax_id in the tax_ids array *)
  let tax_id_idx c tid =
    try
      Array.findi ((=) tid) c.base.tax_ids
    with Not_found -> raise (Tax_id_not_found tid)

  (* add a sequence to the counts for a particular tax_id *)
  let add_seq c tax_id seq =
    let i = tax_id_idx c tax_id in
    incr c.seq_count;
    c.taxid_counts.(i) <- c.taxid_counts.(i) + 1;
    gen_count_by_seq
      c.base.word_length
      (fun j -> c.freq_table.{i, j} <- succ c.freq_table.{i, j})
      seq

end

(* the thing that does actual classification *)
module Classifier = struct
  type t = {
    pc: Preclassifier.base;
    taxid_word_counts: Matrix.matrix;
    boot_matrix: (int, BA.int16_unsigned_elt, BA.c_layout) BA2.t;
    classify_vec: Gsl_vector.vector;
  }

  (* make a classifier from a preclassifier *)
  let make ?(boot_rows = 100) c =
    let open Preclassifier in
    let n_taxids = Array.length c.base.tax_ids
    and n = float_of_int (succ !(c.seq_count)) in
    let prior_counts = Array.init
      c.base.n_words
      (fun j ->
        (* w_j is the prior for seeing word j *)
        let w_j = 0 --^ n_taxids
          |> Enum.map (fun i -> c.freq_table.{i, j})
          |> Enum.sum
          |> float_of_int
        in
        (* (n(w_j) + 0.5) / (N + 1) *)
        (w_j +. 0.5) /. n)
    in
    let taxid_word_counts = BA2.mapij
      (fun i j m ->
        let denom = log (float_of_int c.taxid_counts.(i) +. 1.) in
        (* log (m(w_j) + prior_counts[j]) - denom *)
        log (float_of_int m +. prior_counts.(j)) -. denom)
      BA.float64
      c.freq_table
    |> Matrix.rect_transpose
    and fill_boot_row vec =
      Random.enum_int c.base.n_words
        |> Enum.take (c.base.n_words / c.base.word_length)
        |> Enum.iter (fun i -> vec.{i} <- succ vec.{i})
    and boot_matrix = BA2.create
      BA.int16_unsigned
      BA.c_layout
      boot_rows
      c.base.n_words
    and classify_vec = Gsl_vector.create ~init:0. n_taxids in
    BA2.fill boot_matrix 0;
    0 --^ boot_rows
      |> Enum.iter (fun i -> BA2.slice_left boot_matrix i |> fill_boot_row);
    {pc = c.base; taxid_word_counts; boot_matrix; classify_vec}

  (* find the tax_id associated with a count vector *)
  let classify_vec cf vec =
    let open Preclassifier in
    let dest = cf.classify_vec in
    Gsl_vector.set_zero dest;
    Linear.float_mat_int_vec_mul dest cf.taxid_word_counts vec;
    Gsl_vector.max_index dest |> Array.get cf.pc.tax_ids

  (* fill a vector with counts for a sequence *)
  let count_seq cf seq =
    let open Preclassifier in
    let vec = BA1.create BA.int16_unsigned BA.c_layout cf.pc.n_words in
    BA1.fill vec 0;
    gen_count_by_seq
      cf.pc.word_length
      (fun i -> vec.{i} <- succ vec.{i})
      seq;
    vec

  (* classify a sequence, returning a tax_id *)
  let classify cf seq =
    count_seq cf seq |> classify_vec cf

  (* bootstrap a sequence, returning a map from tax_ids to a float on the range
   * (0, 1] representing the percentage of bootstrappings done that produced a
   * particular tax_id. *)
  let bootstrap cf seq =
    let open Preclassifier in
    let module TIM = Tax_id.TaxIdMap in
    let seq_word_counts = count_seq cf seq in
    let boot_rows = BA2.dim1 cf.boot_matrix in
    if boot_rows = 0 then
      TIM.singleton (classify_vec cf seq_word_counts) 1.
    else (* ... *)
    let booted_word_counts = BA1.create
      BA.int16_unsigned
      BA.c_layout
      cf.pc.n_words
    and incr = 1. /. float_of_int boot_rows |> (+.) in
    0 --^ boot_rows
    |> Enum.fold
        (fun accum i ->
          let boot_row = BA2.slice_left cf.boot_matrix i in
          Linear.int_vec_pairwise_prod booted_word_counts boot_row seq_word_counts;
          let ti = classify_vec cf booted_word_counts in
          TIM.modify_def 0. ti incr accum)
        TIM.empty

  let of_refpkg ?boot_rows word_length rank_idx rp =
    let rank_tax_map = Convex.rank_tax_map_of_refpkg rp
    and gt = Refpkg.get_ref_tree rp in
    let preclassif = IntMap.find rank_idx rank_tax_map
      |> IntMap.values
      |> Tax_id.TaxIdSet.of_enum
      |> Tax_id.TaxIdSet.enum
      |> Array.of_enum
      |> Preclassifier.make Bigarray.int word_length
    (* a map from reference sequence names to chosen-rank tax_ids *)
    and seq_tax_ids = IntMap.find rank_idx rank_tax_map
      |> IntMap.enum
      |> Enum.map (first (Gtree.get_node_label gt))
      |> StringMap.of_enum
    and filter m (k, seq) =
      match StringMap.Exceptionless.find k m with
        | Some v -> Some (v, Alignment.ungap seq)
        | None -> None
    in
    Refpkg.get_aln_fasta rp
      |> Array.enum
      |> Enum.filter_map (filter seq_tax_ids)
      |> Enum.iter (uncurry (Preclassifier.add_seq preclassif));
    make ?boot_rows preclassif

end