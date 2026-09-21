#[compute]
#version 450

#include "./CloudsInc.comp"
// Shared compositing includes the analytic distant-atmosphere tail.
#include "./SunshineCloudsPostCompute.comp"
#include "./CloudsCoarseDensity.comp"
