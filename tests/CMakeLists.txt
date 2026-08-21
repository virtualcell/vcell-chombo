# Two tests per solver: it reports usage when given nothing, and it runs a small
# simulation end to end.
#
# The smoke inputs are hand-written -- VCell normally generates .fvinput files --
# and deliberately minimal: a disc of `cyt` inside a box of `ec`, one volume PDE
# initialised to 1.0 with no flux across the membrane and no reaction, so the
# solution stays 1.0.  That is enough to exercise the whole pipeline (implicit
# function geometry, EB mesh generation, the semi-implicit solve, HDF5 output and
# the .hdf5.zip archiving) but it is NOT a numerical regression suite: nothing
# here compares against baseline values.  Those baselines live with VCell's own
# integration tests.

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
endfunction()

if (OPTION_TARGET_CHOMBO2D_SOLVER)
	add_solver_tests(2)
endif ()
if (OPTION_TARGET_CHOMBO3D_SOLVER)
	add_solver_tests(3)
endif ()
