(* mokaphy v1.0. Copyright (C) 2010  Frederick A Matsen.
 * This file is part of mokaphy. mokaphy is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. pplacer is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with pplacer. If not, see <http://www.gnu.org/licenses/>.
 *)

module Bary = struct
  type prefs = 
    {
      out_fname: string ref;
      use_pp: bool ref;
      weighted: bool ref;
    }

  let out_fname         p = !(p.out_fname)
  let use_pp            p = !(p.use_pp)
  let weighted          p = !(p.weighted)

  let defaults () =
    {
      out_fname = ref "";
      use_pp = ref false;
      weighted = ref true;
    }

  let specl_of_prefs prefs = 
[
  "-p", Arg.Set prefs.use_pp,
  "Use posterior probability.";
  "--unweighted", Arg.Clear prefs.weighted,
  "The unweighted version simply uses the best placement. Default is weighted.";
  "-o", Arg.Set_string prefs.out_fname,
  "Set the filename to write to. Otherwise write to stdout.";
]
end


module Heat = struct
  type mokaphy_prefs = 
    {
      out_fname: string ref;
      use_pp: bool ref;
      p_exp: float ref;
      weighted: bool ref;
      simple_colors: bool ref;
      gray_black_colors: bool ref;
      white_bg: bool ref;
    }
  
  let out_fname         p = !(p.out_fname)
  let use_pp            p = !(p.use_pp)
  let p_exp             p = !(p.p_exp)
  let weighted          p = !(p.weighted)
  let simple_colors     p = !(p.simple_colors)
  let gray_black_colors p = !(p.gray_black_colors)
  let white_bg          p = !(p.white_bg)
  
  let defaults () = 
    { 
      out_fname = ref "";
      use_pp = ref false;
      p_exp = ref 1.;
      weighted = ref true;
      simple_colors = ref false;
      gray_black_colors = ref false;
      white_bg = ref false;
    }
  
  let specl_of_prefs prefs = 
[
"-o", Arg.Set_string prefs.out_fname,
"Set the filename to write to. Otherwise write to stdout.";
"-p", Arg.Set prefs.use_pp,
"Use posterior probability.";
"--exp", Arg.Set_float prefs.p_exp,
"The exponent for the integration, i.e. the value of p in Z_p.";
"--unweighted", Arg.Clear prefs.weighted,
    "The unweighted version simply uses the best placement. Default is weighted.";
"--simpleColors", Arg.Set prefs.simple_colors,
"Use only 100% red and blue to signify the sign of the KR along that edge.";
"--grayBlackColors", Arg.Set prefs.gray_black_colors,
"Use gray and black in place of red and blue to signify the sign of the KR along that edge.";
"--whitebg", Arg.Set prefs.white_bg,
"Make colors for the heat tree which are compatible with a white background.";
]
end


module KR = struct
  type mokaphy_prefs = 
    {
      use_pp: bool ref;
      verbose: bool ref;
      normal: bool ref;
      n_samples: int ref;
      out_fname: string ref;
      density: bool ref;
      p_plot: bool ref;
      box_plot: bool ref;
      p_exp: float ref;
      weighted: bool ref;
      seed: int ref;
      matrix: bool ref;
      bary_density: bool ref;
      ddensity: bool ref;
    }
  
  let use_pp            p = !(p.use_pp)
  let verbose           p = !(p.verbose)
  let normal            p = !(p.normal)
  let n_samples         p = !(p.n_samples)
  let out_fname         p = !(p.out_fname)
  let density           p = !(p.density)
  let p_plot            p = !(p.p_plot)
  let box_plot          p = !(p.box_plot)
  let p_exp             p = !(p.p_exp)
  let weighted          p = !(p.weighted)
  let seed              p = !(p.seed)
  let matrix            p = !(p.matrix)
  let bary_density      p = !(p.bary_density)
  let ddensity          p = !(p.ddensity)
  
  let defaults () = 
    { 
      use_pp = ref false;
      verbose = ref false;
      normal = ref false;
      n_samples = ref 0;
      out_fname = ref "";
      density = ref false;
      p_plot = ref false;
      box_plot = ref false;
      p_exp = ref 1.;
      weighted = ref true;
      seed = ref 1;
      matrix = ref false;
      bary_density = ref false;
      ddensity = ref false;
    }
  
  (* arguments *)
  let specl_of_prefs prefs = [
    "-o", Arg.Set_string prefs.out_fname,
    "Set the filename to write to. Otherwise write to stdout.";
    "--verbose", Arg.Set prefs.verbose,
    "Verbose running.";
    "-p", Arg.Set prefs.use_pp,
    "Use posterior probability.";
    "--exp", Arg.Set_float prefs.p_exp,
    "The exponent for the integration, i.e. the value of p in Z_p.";
    "--unweighted", Arg.Clear prefs.weighted,
        "The unweighted version simply uses the best placement. Default is weighted.";
    "--density", Arg.Set prefs.density,
    "write out a shuffle density data file for each pair.";
    "--pplot", Arg.Set prefs.p_plot,
        "write out a plot of the distances when varying the p for the Z_p calculation";
    "--box", Arg.Set prefs.box_plot,
        "write out a box and point plot showing the original sample distances compared to the shuffled ones.";
    "-s", Arg.Set_int prefs.n_samples,
        ("Set how many samples to use for significance calculation (0 means \
        calculate distance only). Default is "^(string_of_int (n_samples prefs)));
    "--seed", Arg.Set_int prefs.seed,
    "Set the random seed, an integer > 0.";
    "--normal", Arg.Set prefs.normal,
    "Use the normal approximation rather than shuffling. This disables the --pplot and --box options if set.";
    "--bary_density", Arg.Set prefs.bary_density,
    "Write out a density plot of barycenter distance versus shuffled version for each pair.";
    "--matrix", Arg.Set prefs.matrix,
    "Use the matrix formulation to calculate distance and p-value.";
    "--ddensity", Arg.Set prefs.ddensity,
      "Make distance-by-distance densities.";
    ]
end 
