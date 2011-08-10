(* a type for three-taxon trees which is useful for likelihood calculations.
 * we assume that the distance from the dist do the prox is fixed. see
 * set_dist_bl.
 *)

open Ppatteries

let n_like_calls = ref 0

type three_tax = {
  model  : Model.t;
  util_v : Gsl_vector.vector; (* should be as long as the number of sites *)
  prox   : Glv_edge.t;      (* the proximal glv *)
  dist   : Glv_edge.t;      (* the distal glv *)
  pend   : Glv_edge.t;      (* the pendant, i.e. query glv *)
}

let get_pend_bl tt = Glv_edge.get_bl tt.pend
let get_dist_bl tt = Glv_edge.get_bl tt.dist
let get_prox_bl tt = Glv_edge.get_bl tt.prox
let get_cut_bl tt = (get_dist_bl tt) +. (get_prox_bl tt)

let make model util_v ~prox ~dist ~pend =
  {
    model  = model;
    util_v = util_v;
    prox   = prox;
    dist   = dist;
    pend  = pend;
  }

let log_like tt =
  Glv.log_like3
    tt.util_v
    tt.model
    (Glv_edge.get_evolv tt.prox)
    (Glv_edge.get_evolv tt.dist)
    (Glv_edge.get_evolv tt.pend)

let set_pend_bl tt pend_bl =
  Glv_edge.set_bl tt.model tt.pend pend_bl

let set_dist_bl tt dist_bl =
  let prox_bl = (get_cut_bl tt) -. dist_bl in
  assert(prox_bl >= 0.);
  Glv_edge.set_bl tt.model tt.dist dist_bl;
  Glv_edge.set_bl tt.model tt.prox prox_bl

(* we minimize the negative of the log likelihood *)
let optimize_something tolerance set_fun ~start_v ~min_v ~max_v tt =
  if min_v = max_v then start_v
  else begin
    let opt_fun value =
      incr n_like_calls;
      set_fun value;
      -. (log_like tt)
    in
    Minimization.brent
        opt_fun start_v min_v max_v tolerance
  end

let optimize_pend_bl tolerance max_value tt =
  optimize_something
    tolerance (set_pend_bl tt) ~start_v:(get_pend_bl tt)
    ~min_v:1e-8 ~max_v:max_value tt

let optimize_dist_bl tolerance tt =
  optimize_something
    tolerance (set_dist_bl tt) ~start_v:(get_dist_bl tt)
    ~min_v:0. ~max_v:(get_cut_bl tt) tt

let optimize tolerance max_pend_bl max_iter tt =
  let rec aux which_step prev_pend prev_dist =
    if which_step > max_iter then
      raise Minimization.ExceededMaxIter;
    let curr_pend = optimize_pend_bl tolerance max_pend_bl tt
    and curr_dist = optimize_dist_bl tolerance tt in
    if (abs_float (prev_pend -. curr_pend) > tolerance ||
        abs_float (prev_dist -. curr_dist) > tolerance)
      then aux (which_step+1) curr_pend curr_dist
      else ()
  in
  n_like_calls := 0;
  let () = aux 1 (get_pend_bl tt) (get_dist_bl tt) in
  !n_like_calls

let get_results tt = (log_like tt, get_pend_bl tt, get_dist_bl tt)

let copy_bls ~src ~dest =
  set_pend_bl dest (get_pend_bl src);
  set_dist_bl dest (get_dist_bl src)

(* write out the likelihood surface, with base_ll discounted. this is what
 * integrate actually integrates, sampled on an integer-plus-half lattice. *)
let write_like_surf prior max_pend tt fname n_samples =
  let base_ll = log_like tt
  and cut_bl = get_cut_bl tt in
  let dist_incr = cut_bl /. (float_of_int n_samples)
  and pend_incr = max_pend /. (float_of_int n_samples)
  and float_and_half i = 0.5 +. (float_of_int i)
  and ch = open_out fname
  in
  for i=0 to n_samples-1 do
    set_dist_bl tt (dist_incr *. (float_and_half i));
    for j=0 to n_samples-1 do
      let pend_bl = pend_incr *. (float_and_half j) in
      set_pend_bl tt pend_bl;
      Printf.fprintf ch "%g\t"
        ((exp ((log_like tt) -. base_ll)) *. (prior pend_bl));
    done;
    Printf.fprintf ch "\n";
  done;
  close_out ch

(* Find an appropriate upper limit for pendant branch length integration. If we
 * come up with a resonable upper limit then we get better results than
 * integrating out to max_pend.
 * This function uses the current pend branch length and moves right in
 * increments of the current branch length, stopping when the ll function drops
 * below 1e-10*orig_ll.
 * Note 1: this does change the pend_bl.
 * Note 2: this assumes that the likelihood function is monotonic in the pendant
 * branch length.
 *)
let find_upper_limit max_pend prior orig_ll tt =
  let log_prior x = log (prior x)
  and orig_pend_bl = get_pend_bl tt
  in
  let log_cutoff = -10. +. orig_ll +. (log_prior orig_pend_bl) in
  let rec aux next_pend_bl =
    set_pend_bl tt next_pend_bl;
    if log_cutoff > (log_like tt) +. (log_prior next_pend_bl) then get_pend_bl tt
    else if next_pend_bl > max_pend then max_pend
    else aux (orig_pend_bl +. next_pend_bl)
  in
  aux (get_pend_bl tt)

(* The idea here is to properly integrate log likelihood functions by removing
 * some portion so that when we actually do the integration, we don't have
 * underflow problems.
 * We use the original branch lengths in tt to get a baseLL.
 * This calculates then
 * baseLL + \log ( cut_bl^{-1} \int \int \exp(llF - baseLL) * prior(x) dx dy )
 * Note: modifies the branch lengths in tt!
*)
let calc_marg_prob prior rel_err max_pend tt =
  let abs_err = 0. in (* do not specify an absolute error *)
  (* first calculate a base_ll. we use the given base_pend and the midpoint of
   * the edge *)
  let base_ll = log_like tt
  and cut_bl = get_cut_bl tt in
  let upper_limit = find_upper_limit max_pend prior base_ll tt in
  try
    base_ll +.
      log
        ((Integration.value_integrate
          (fun dist_bl ->
            set_dist_bl tt dist_bl;
            Integration.value_integrate
              (fun pend_bl ->
                set_pend_bl tt pend_bl;
                (exp ((log_like tt) -. base_ll))
                  *. (prior pend_bl))
              0. upper_limit ~abs_err ~rel_err)
          0. cut_bl ~abs_err ~rel_err)
        /. cut_bl)
        (* normalize out the integration over a branch length *)
  with
  | Gsl_error.Gsl_exn(error_num, error_str) ->
      if error_num = Gsl_error.ETOL then begin
(* Integration failed to reach tolerance with highest-order rule *)
        Printf.printf "Warning: %s\n" error_str;
(* return the base LL *)
        base_ll
      end
      else
        raise (Gsl_error.Gsl_exn(error_num, error_str))

