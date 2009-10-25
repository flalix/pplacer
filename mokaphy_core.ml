(* mokaphy v0.3. Copyright (C) 2009  Frederick A Matsen.
 * This file is part of mokaphy. mokaphy is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer. If not, see <http://www.gnu.org/licenses/>.
*)
open Fam_batteries
open MapsSets

type result = 
  {
    distance : float;
    p_value : float;
  }

let get_distance r = r.distance
let get_p_value r = r.p_value

(* makes an array of shuffled placeruns (identity of being in first or second
 * one shuffled randomly, but number in each the same) *)
let make_shuffled_prs n_shuffles pr1 pr2 = 
  let pq1 = Placerun.get_pqueries pr1
  and pq2 = Placerun.get_pqueries pr2
  in
  let pquery_arr = Array.of_list (pq1 @ pq2)
  and n1 = List.length pq1
  and n2 = List.length pq2
  in
  let pquery_sub start len = 
    Array.to_list (Array.sub pquery_arr start len)
  in
  let make_pr pr num pqueries = 
    Placerun.make
      (Placerun.get_ref_tree pr)
      (Placerun.get_prefs pr)
      ((Placerun.get_name pr)^"_shuffle_"^(string_of_int num))
      pqueries
  in
  ListFuns.init 
    n_shuffles
    (fun num ->
      Mokaphy_base.shuffle pquery_arr;
      (make_pr pr1 num (pquery_sub 0 n1),
      make_pr pr2 num (pquery_sub n1 n2)))

let pair_core prefs criterion pr1 pr2 =
  let p = (Mokaphy_prefs.p_exp prefs) in
  let weighting = 
    if Mokaphy_prefs.weighted prefs then Placerun_distance.Weighted 
    else Placerun_distance.Unweighted 
  in
  let calc_dist = 
    Placerun_distance.pair_dist 
      criterion 
      weighting 
      p in
  let original_dist = calc_dist pr1 pr2 in
  if Mokaphy_prefs.matrix_check prefs then
    Matrix_check.check pr1 pr2;
  if Mokaphy_prefs.heat_tree prefs then
    Heat_tree.write_heat_tree criterion weighting p pr1 pr2;
  if Mokaphy_prefs.shuffle prefs then begin
    (* shuffle mode *)
    let shuffled_list = 
      make_shuffled_prs (Mokaphy_prefs.n_samples prefs) pr1 pr2 in
    let shuffled_dists = 
      List.map 
        (fun (spr1,spr2) -> calc_dist spr1 spr2)
        shuffled_list
    in
    if Mokaphy_prefs.histo prefs then
      R_plots.write_histogram 
        "histo"
        (Placerun.get_name pr1)
        (Placerun.get_name pr2)
        original_dist 
        shuffled_dists 
        p;
    if Mokaphy_prefs.p_plot prefs then
      R_plots.write_p_plot criterion weighting pr1 pr2;
    if Mokaphy_prefs.box_plot prefs then
      R_plots.write_boxplot criterion weighting pr1 pr2 shuffled_list;
    { distance = original_dist;
      p_value = 
        Mokaphy_base.list_onesided_pvalue shuffled_dists original_dist}
  end
  else begin
    (* normal approx mode *)
    let resampled_dists = 
      Normal_approx.resampled_distn 
        (Mokaphy_prefs.n_samples prefs) criterion p pr1 pr2
    in
    (* here we shadow original_dist with one we know is unweighted *)
    let original_dist = 
      Placerun_distance.pair_dist 
        criterion 
        Placerun_distance.Unweighted 
        p 
        pr1 
        pr2
    in
    R_plots.write_histogram 
      "normal"
      (Placerun.get_name pr1)
      (Placerun.get_name pr2)
      original_dist 
      resampled_dists
      p;
    { distance = original_dist;
      p_value = 
        Mokaphy_base.list_onesided_pvalue resampled_dists original_dist}
  end


(* core
 * run pair_core for each unique pair 
 *)
let core prefs criterion ch pr_arr = 
  Printf.printf "calculating Z_%g distance...\n" 
                (Mokaphy_prefs.p_exp prefs);
  let u = 
    Uptri.init
      (Array.length pr_arr)
      (fun i j ->
        pair_core 
          prefs
          criterion
          pr_arr.(i) 
          pr_arr.(j))
  in
  let names = Array.map Placerun.get_name pr_arr in
  Printf.fprintf ch "distances\n"; 
  Mokaphy_base.write_named_float_uptri ch names (Uptri.map get_distance u);
  Printf.fprintf ch "\np-values\n"; 
  Mokaphy_base.write_named_float_uptri ch names (Uptri.map get_p_value u);
