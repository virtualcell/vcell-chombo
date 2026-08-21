# Smoke coverage only for now: confirm each solver binary links, starts, and
# reports its usage.  There is no numerical regression suite in this repo yet --
# the Chombo solver's reference outputs live with VCell's integration tests.

foreach (dim 2 3)
	if (dim EQUAL 2 AND NOT OPTION_TARGET_CHOMBO2D_SOLVER)
		continue()
	endif ()
	if (dim EQUAL 3 AND NOT OPTION_TARGET_CHOMBO3D_SOLVER)
		continue()
	endif ()

	if (OPTION_TARGET_PARALLEL)
		set(exe VCellChombo${dim}D_x64parallel)
	else ()
		set(exe VCellChombo${dim}D_x64)
	endif ()

	add_test(NAME ${exe}_usage COMMAND ${exe})
	# The solver prints its usage to Chombo's pout() stream and exits non-zero
	# when handed no input file.
	set_tests_properties(${exe}_usage PROPERTIES WILL_FAIL TRUE)
endforeach ()
