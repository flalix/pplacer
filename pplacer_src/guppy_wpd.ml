open Subcommand
open Guppy_cmdobjs
open Ppatteries

let wpd_of_placerun indiv_of pr =
  Guppy_pd.total_along_mass
    (Placerun.get_ref_tree pr)
    (indiv_of pr)
    (fun r -> 2. *. (min !r (1. -. !r)))

class cmd () =
object (self)
  inherit subcommand () as super
  inherit mass_cmd () as super_mass
  inherit placefile_cmd () as super_placefile
  inherit output_cmd () as super_output

  method specl =
    super_mass#specl
    @ super_output#specl

  method desc =
"calculate weighted phylogenetic diversity of placefiles"
  method usage = "usage: wpd [options] placefile[s]"

  method private placefile_action prl =
    let transform, weighting, criterion = self#mass_opts in
    let indiv_of = Mass_map.Indiv.of_placerun transform weighting criterion in
    let wpd = wpd_of_placerun indiv_of in
    List.iter
      (fun pr ->
        wpd pr |> Printf.printf "%s: %g\n" (Placerun.get_name pr))
      prl

end