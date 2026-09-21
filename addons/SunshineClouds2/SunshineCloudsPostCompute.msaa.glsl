#[compute]
#version 450

#define MSAA_ENABLED 1

#include "./CloudsInc.comp"
// Shared compositing includes the analytic distant-atmosphere tail.
#include "./SunshineCloudsPostCompute.comp"
#include "./CloudsCoarseDensity.comp"
