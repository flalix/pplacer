open OUnit

let suite = [
  "kr_distance" >::: Test_kr_distance.suite;
  "power_iteration" >::: Test_power_iteration.suite;
  "pca" >::: Test_pca.suite;
  (*"som" >::: Test_som.suite;*)
  "heat" >::: Test_heat.suite;
  "edge_rdist" >::: Test_edge_rdist.suite;
  "edpl" >::: Test_edpl.suite;
  "gaussian" >::: Test_gaussian.suite;
  "pd" >::: Test_pd.suite;
  "fpd" >::: Test_fpd.suite;
  "rarefact" >::: Test_rarefact.suite;
  "islands" >::: Test_islands.suite;
  "compress" >::: Test_compress.suite;
  "error" >::: Test_error.suite;
  "overlap" >::: Test_overlap.suite;
  "newick_bark" >::: Test_newick_bark.suite;
  "splitify" >::: Test_splitify.suite;
]
