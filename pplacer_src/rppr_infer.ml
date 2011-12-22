open Subcommand
open Guppy_cmdobjs
open Ppatteries
open Convex

let prune_notax sizemim st =
  let open Stree in
  let rec should_prune i =
    let sizem = IntMap.find i sizemim in
    ColorMap.cardinal sizem = 1 && ColorMap.mem Tax_id.NoTax sizem
  and aux = function
    | Leaf _ as l -> l
    | Node (i, subtrees) ->
      List.filter_map
        (fun t ->
          let j = top_id t in
          if should_prune j then None else Some (aux t))
        subtrees
      |> node i
  in
  aux st

let place_on_rp prefs rp gt =
  let td = Refpkg.get_taxonomy rp in
  Prefs.(
    prefs.calc_pp := true;
    prefs.informative_prior := true;
    prefs.keep_at_most := 20;
    prefs.keep_factor := 0.001;
    prefs.max_strikes := 20);
  let results = RefList.empty () in
  let placerun_cb pr =
    Placerun.get_pqueries pr
    |> List.iter
        (fun pq ->
          let classif = Pquery.place_list pq
            |> List.map Placement.classif
            |> Tax_taxonomy.list_mrca td
          in
          List.iter
            (Tuple3.curry
               identity
               classif
               (Pquery.best_place Placement.ml_ratio pq)
                |- RefList.push results)
            (Pquery.namel pq))
  in
  File.with_temporary_out (fun ch tree_file ->
    Newick_gtree.write ch gt;
    prefs.Prefs.tree_fname := tree_file;
    dprintf "%s\n" tree_file;
    Pplacer_run.run_file
      ~placerun_cb
      prefs
      (Refpkg.get_item_path rp "aln_fasta"));
  RefList.to_list results

class cmd () =
object (self)
  inherit subcommand () as super
  inherit refpkg_cmd ~required:true as super_refpkg
  inherit tabular_cmd () as super_tabular

  val processes = flag "-j"
    (Formatted (2, "The number of processes to run pplacer with. default: %d"))

  method specl =
    super_refpkg#specl
  @ super_tabular#specl
  @ [
    int_flag processes;
  ]

  method desc = "infer classifications of unclassified sequences in a reference package"
  method usage = "usage: infer [options] -c my.refpkg"

  method action _ =
    let rp = self#get_rp in
    let gt = Refpkg.get_ref_tree rp
    and td = Refpkg.get_taxonomy rp
    and seqinfo = Refpkg.get_seqinfom rp in
    let leaf_labels = Newick_gtree.leaf_label_map gt in
    let colors =
      IntMap.map
        (Tax_seqinfo.tax_id_by_node_label seqinfo)
        leaf_labels
    and seq_nodes = IntMap.enum leaf_labels
      |> Enum.map swap
      |> StringMap.of_enum
    and st = Gtree.get_stree gt in
    let taxa_set colorm needle =
      IntMap.fold
        (fun i ti accum -> if ti = needle then IntSet.add i accum else accum)
        colorm
        IntSet.empty
    and sizemim, _ = build_sizemim_and_cutsetim (colors, st) in
    let dm = Edge_rdist.build_pairwise_dist gt
    and no_tax = taxa_set colors Tax_id.NoTax in
    let max_taxdist colorm ti =
      let ta = taxa_set colorm ti |> IntSet.elements |> Array.of_list in
      Uptri.init
        (Array.length ta)
        (fun i j -> Edge_rdist.find_pairwise_dist dm ta.(i) 0. ta.(j) 0.)
      |> Uptri.to_array
      |> Array.max
    and st' = prune_notax sizemim st in
    let gt' = Gtree.set_stree gt st' in
    let prefs = Prefs.defaults () in
    prefs.Prefs.refpkg_path := fv refpkg_path;
    prefs.Prefs.children := fv processes;
    let results = place_on_rp prefs rp gt' in
    let colors' =
      List.fold_left
        (fun accum (tid, _, seq) ->
          IntMap.add (StringMap.find seq seq_nodes) tid accum)
        colors
        results
    and best_placements =
      List.fold_left
        (fun accum (_, p, seq) ->
          IntMap.add (StringMap.find seq seq_nodes) p accum)
        IntMap.empty
        results
    in
    let rankmap = IntMap.enum colors' |> build_rank_tax_map td some in
    let highest_rank, _ = IntMap.max_binding rankmap in
    IntSet.fold
      (fun i accum ->
        let p = IntMap.find i best_placements in
        dprintf ~l:2 "%s:\n" (Gtree.get_node_label gt i);
        let rec aux rank =
          if not (IntMap.mem rank rankmap) then aux (rank - 1) else (* ... *)
          let taxm = IntMap.find rank rankmap in
          if not (IntMap.mem i taxm) then aux (rank - 1) else (* ... *)
          let ti = IntMap.find i taxm in
          let others = taxa_set taxm ti |> flip IntSet.diff no_tax
          and max_pairwise = max_taxdist taxm ti in
          let max_placement = others
            |> IntSet.enum
            |> Enum.map
                (fun j ->
                  Edge_rdist.find_pairwise_dist
                    dm
                    j
                    0.
                    (Placement.location p)
                    (Placement.distal_bl p))
            |> Enum.reduce max
            |> (+.) (Placement.pendant_bl p)
          in
          dprintf ~l:2 "  %s -> %s (%s): %b %g max %g max+pend\n"
            (Tax_taxonomy.get_rank_name td rank)
            (Tax_id.to_string ti)
            (Tax_taxonomy.get_tax_name td ti)
            (max_placement < max_pairwise)
            max_pairwise
            max_placement;
          if max_placement < max_pairwise then
            ti
          else if rank = 0 then
            failwith
              (Printf.sprintf "no inferred taxid for %s" (Tax_id.to_string ti))
          else
            aux (rank - 1)
        in
        let ti = aux highest_rank in
        [Gtree.get_node_label gt i;
         Tax_id.to_string ti;
         Tax_taxonomy.get_tax_name td ti]
        :: accum
      )
      no_tax
      []
    |> self#write_ll_tab

end
