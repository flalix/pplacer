(* pplacer v0.3. Copyright (C) 2009  Frederick A Matsen.
 * This file is part of pplacer. pplacer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer.  If not, see <http://www.gnu.org/licenses/>.
*)

open MapsSets

(* writing the .loc.fasta file *)
let write_loc_file fname_base unplaced_seqs placed_map =
  let out_ch = open_out (fname_base^".loc.fasta") in
  let print_pquery_seq pq =
    Printf.fprintf out_ch ">%s\n%s\n" 
      (Pquery.name pq) 
      (Pquery.seq pq)
  in
  if unplaced_seqs <> [] then
    Printf.fprintf out_ch ">unplaced_sequences\n\n";
  List.iter print_pquery_seq unplaced_seqs;
  IntMap.iter
    (fun loc pquery_list ->
      Printf.fprintf out_ch ">placed_at_%d\n\n" loc;
      List.iter print_pquery_seq pquery_list)
    placed_map;
  close_out out_ch


(* writing various tree formats *)


let trees_to_file fname trees = 
  let out_ch = open_out fname in
  List.iter (Stree_io.write_newick out_ch) trees;
  close_out out_ch

let make_zero_leaf bl taxon = 
  Stree.inform_stree 
    (Stree.leaf 0)
    (Stree.opt_add_info 0 ~bl ~taxon Stree.emptyInfo)

let tree_by_map f ref_tree placed_map = 
  Stree.add_subtrees_by_map
    ref_tree
    (IntMap.mapi f placed_map)

let tog_tree ref_tree placed_map = 
  tree_by_map
    (fun _ ->
      List.map
        (fun pquery ->
          let best = Pquery.best_place Placement.ml_ratio pquery in
          (Placement.distal_bl best,
          make_zero_leaf 
            (Placement.pendant_bl best)
            (Pquery.name pquery))))
    ref_tree
    placed_map
        
let num_tree bogus_bl ref_tree placed_map = 
  tree_by_map
    (fun loc pqueries ->
      [(Stree.get_bl ref_tree loc,
      make_zero_leaf 
        bogus_bl
        (Printf.sprintf "%d_at_%d" (List.length pqueries) loc))])
    ref_tree
    placed_map

let write_tog_file fname_base ref_tree placed_map = 
  trees_to_file 
    (fname_base^".tog.tre") 
    [tog_tree ref_tree placed_map]

let write_num_file bogus_bl fname_base ref_tree placed_map = 
  trees_to_file 
    (fname_base^".num.tre") 
    [num_tree bogus_bl ref_tree placed_map]
