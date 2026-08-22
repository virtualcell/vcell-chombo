# Three tests per solver: it reports usage when given nothing, it runs a small
# simulation end to end, and it still computes what it used to.
#
# All the inputs are hand-written -- VCell normally generates .fvinput files --
# around the same geometry: a disc (or sphere) of `cyt` inside a box of `ec`, one
# volume PDE, zero flux across the membrane and no reaction.
#
#   smoke${DIM}d    starts uniform at 1.0 and stays there. Exercises the whole
#                   pipeline -- implicit function geometry, EB mesh generation,
#                   the semi-implicit solve, HDF5 output, zip archiving -- and
#                   is fast enough to be the first thing that fails.
#
#   regress${DIM}d  starts as a Gaussian bump, so the field has to actually
#                   diffuse, and the final timepoint is compared value by value
#                   against a stored baseline. A uniform field would satisfy any
#                   baseline trivially, which is why this is a separate case
#                   rather than a tolerance bolted onto the smoke run.

# Reads the solver's HDF5 output for the regression comparison, and writes the
# baselines too. A small tool rather than h5diff because the Conan HDF5 package
# ships no command line utilities and the project already links the C API.
add_executable(compare_solution compare_solution.cpp)
target_link_libraries(compare_solution PRIVATE HDF5::HDF5)

function(add_solver_tests DIM)
	if (OPTION_TARGET_PARALLEL)
		set(exe VCellChombo${DIM}D_x64parallel)
	else ()
		set(exe VCellChombo${DIM}D_x64)
	endif ()

	add_test(NAME ${exe}_usage COMMAND ${exe})
	# The solver prints its usage and exits non-zero when handed no input file.
	set_tests_properties(${exe}_usage PROPERTIES WILL_FAIL TRUE)

	add_test(NAME ${exe}_smoke COMMAND ${CMAKE_COMMAND}
			-DSOLVER=$<TARGET_FILE:${exe}>
			-DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/resources/smoke${DIM}d.fvinput
			-DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/smoke${DIM}d
			-DBASE_NAME=SimID_smoke${DIM}d_0_
			# TIME_INTERVALS: stop at 0.01 in steps of 0.005, keeping every
			# step, plus the initial condition.
			-DEXPECTED_TIMEPOINTS=3
			-P ${CMAKE_CURRENT_SOURCE_DIR}/RunSolverSmokeTest.cmake)
	set_tests_properties(${exe}_smoke PROPERTIES TIMEOUT 600)

	add_test(NAME ${exe}_regression COMMAND ${CMAKE_COMMAND}
			-DSOLVER=$<TARGET_FILE:${exe}>
			-DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/resources/regress${DIM}d.fvinput
			-DWORK_DIR=${CMAKE_CURRENT_BINARY_DIR}/regress${DIM}d
			-DBASE_NAME=SimID_regress${DIM}d_0_
			# TIME_INTERVALS: stop at 0.02 in steps of 0.0025 keeping every second
			# one, plus the initial condition.
			-DEXPECTED_TIMEPOINTS=5
			-DBASELINE=${CMAKE_CURRENT_SOURCE_DIR}/resources/regress${DIM}d.baseline.txt
			-DCOMPARATOR=$<TARGET_FILE:compare_solution>
			-DRTOL=${VCELL_CHOMBO_REGRESSION_RTOL}
			-DATOL=${VCELL_CHOMBO_REGRESSION_ATOL}
			-P ${CMAKE_CURRENT_SOURCE_DIR}/RunSolverSmokeTest.cmake)
	set_tests_properties(${exe}_regression PROPERTIES TIMEOUT 600)
endfunction()

# Tolerances for the regression comparison. Deliberately settable: the same
# source compiled by a different GCC, or for a different architecture, will not
# reproduce these fields bit for bit, and the right floor is an empirical
# question rather than a matter of taste. See tests/README.md for what has
# actually been measured.
set(VCELL_CHOMBO_REGRESSION_RTOL "1e-9" CACHE STRING "relative tolerance for the solution regression tests")
set(VCELL_CHOMBO_REGRESSION_ATOL "1e-12" CACHE STRING "absolute tolerance for the solution regression tests")

if (OPTION_TARGET_CHOMBO2D_SOLVER)
	add_solver_tests(2)
endif ()
if (OPTION_TARGET_CHOMBO3D_SOLVER)
	add_solver_tests(3)
endif ()
