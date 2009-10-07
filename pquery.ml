(* pplacer v0.3. Copyright (C) 2009  Frederick A Matsen.
 * This file is part of pplacer. pplacer is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer. If not, see <http://www.gnu.org/licenses/>.
 *)

(* pquery stands for placed query, which means that it is a named query sequence
 * with the placement information (which may be empty).
 *)

open MapsSets

let sort_placement_list criterion pl =
  List.sort 
    (fun x y -> - Placement.compare_placements criterion x y) 
    pl

let rec is_decreasing criterion = function
  | x::y::l -> 
      if criterion x >= criterion y then is_decreasing criterion l
      else false
  | _ -> true

type pquery = 
  {
    name       : string;
    seq        : string;
    place_list : Placement.placement list;
  }

let name p       = p.name
let seq p        = p.seq
let place_list p = p.place_list

let opt_best_place criterion pq =
  assert(is_decreasing criterion (place_list pq));
  match place_list pq with
  | best::_ -> Some best
  | [] -> None 

let opt_best_location criterion pq = 
  match opt_best_place criterion pq with
  | Some place -> Some (Placement.location place)
  | None -> None

let best_place criterion pq = 
  match opt_best_place criterion pq with
  | Some place -> place
  | None -> failwith "best_place: no places!"

let best_location criterion pq = 
  match opt_best_location criterion pq with
  | Some loc -> loc
  | None -> failwith "best_location: no locations!"

let is_placed pq = 
  match place_list pq with
  | [] -> false
  | _ -> true

let make criterion ~name ~seq pl = 
  { 
    name = name; 
    seq = seq; 
    place_list = sort_placement_list criterion pl
  }

let make_ml_sorted = make Placement.ml_ratio
let make_pp_sorted = make Placement.post_prob

let sort criterion pq = 
  if is_decreasing criterion (place_list pq) then pq
  else { pq with 
         place_list = sort_placement_list criterion (place_list pq) }
  
let make_map_by_best_loc criterion pquery_list = 
  let (placed_l, unplaced_l) = 
    List.partition is_placed pquery_list in
  (unplaced_l,
    IntMapFuns.of_f_list_listly
      ~key_f:(best_location criterion)
      ~val_f:(fun x -> x)
      placed_l)
