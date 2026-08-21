# Drives the vendored Chombo build (chombo/lib/GNUmakefile) from CMake.
#
# Chombo has no CMake build of its own; it ships a large, self-contained GNU
# make system that also runs the ChomboFortran preprocessor (perl) over the
# .ChF sources.  Rather than reimplement that, we invoke it -- but with every
# configuration variable passed on the `make` command line, where it overrides
# anything in a makefile.  That keeps the source tree free of the generated
# mk/Make.defs.local that the old in-tree build used to copy into place, so two
# builds with different settings can share one checkout.
#
# Two quirks of Chombo's makefiles are worth knowing:
#
#   * Dependency generation is written for csh (`CSHELLCMD`), which is not
#     installed by default on modern Linux or macOS.  The command it runs is a
#     plain pipeline, so /bin/sh executes it identically.
#   * Everything under lib/ (generated *_F.H headers, lib/include, the archives)
#     is shared between dimensions.  The 2D and 3D builds must therefore be
#     serialized, and each one's output snapshotted before the next runs.

set(CHOMBO_SOURCE_DIR "${PROJECT_SOURCE_DIR}/chombo" CACHE PATH "vendored Chombo checkout")
set(CHOMBO_LIB_DIR "${CHOMBO_SOURCE_DIR}/lib")

# Link order matters for static archives: dependants first.
set(CHOMBO_LINK_ORDER
		mftools
		ebamrelliptic
		ebamrtools
		ebtools
		amrelliptic
		amrtools
		workshop
		boxtools
		basetools)

include(ProcessorCount)
ProcessorCount(_chombo_default_jobs)
if (_chombo_default_jobs EQUAL 0)
	set(_chombo_default_jobs 1)
endif ()
set(CHOMBO_BUILD_JOBS "${_chombo_default_jobs}" CACHE STRING "parallelism for the Chombo GNU make build")

find_program(CHOMBO_MAKE_PROGRAM NAMES gmake make REQUIRED
		DOC "GNU make, used to build the vendored Chombo libraries")
find_program(CHOMBO_PERL_PROGRAM NAMES perl REQUIRED
		DOC "perl, used by Chombo's ChomboFortran preprocessor")

# Chombo picks its compiler flag set by matching the basename of $(CXX)/$(FC)
# against names it knows (g++, gfortran, icpc, ...).  CMake often hands us the
# generic /usr/bin/c++ driver, which Chombo would not recognise -- it would fall
# back to a bare `-O` with none of the warning suppressions the sources expect.
function(_chombo_compiler_name out_var compiler_path compiler_id)
	get_filename_component(_name "${compiler_path}" NAME_WE)
	if (_name STREQUAL "c++" OR _name STREQUAL "cc")
		if (compiler_id STREQUAL "GNU")
			set(_name "g++")
		elseif (compiler_id MATCHES "Clang")
			set(_name "clang++")
		endif ()
	endif ()
	set(${out_var} "${_name}" PARENT_SCOPE)
endfunction()

##
# add_chombo_dimension(<dim> [DEPENDS <target>])
#
# Defines a target `chombo_<dim>d` that builds the Chombo libraries for
# CH_SPACEDIM=<dim>, and sets in the caller's scope:
#
#   CHOMBO_<dim>D_INCLUDE_DIR  -- snapshot of Chombo's public headers
#   CHOMBO_<dim>D_LIBRARIES    -- the archives, in link order
##
function(add_chombo_dimension DIM)
	cmake_parse_arguments(ARG "" "" "DEPENDS" ${ARGN})

	set(_out "${CMAKE_BINARY_DIR}/chombo/${DIM}d")
	set(_stamp "${_out}/chombo${DIM}d.stamp")

	set(_libs "")
	foreach (base ${CHOMBO_LINK_ORDER})
		list(APPEND _libs "${_out}/lib/lib${base}${DIM}d.a")
	endforeach ()

	_chombo_compiler_name(_cxx_name "${CMAKE_CXX_COMPILER}" "${CMAKE_CXX_COMPILER_ID}")
	_chombo_compiler_name(_fc_name "${CMAKE_Fortran_COMPILER}" "${CMAKE_Fortran_COMPILER_ID}")

	# Chombo's `make lib` only compiles and archives, so HDFLIBFLAGS is never
	# actually used -- but lib/GNUmakefile prints a scary warning when it is
	# empty, and the include flags very much are needed.
	set(_hdf_inc_flags "-DH5_USE_16_API")
	foreach (dir ${HDF5_INCLUDE_DIRS})
		string(APPEND _hdf_inc_flags " -I${dir}")
	endforeach ()

	if (CMAKE_SIZEOF_VOID_P EQUAL 8)
		set(_use64 TRUE)
	else ()
		set(_use64 FALSE)
	endif ()

	add_custom_command(
			OUTPUT ${_libs} ${_stamp}
			COMMENT "Building Chombo ${DIM}D libraries (this takes a few minutes)"
			COMMAND ${CHOMBO_MAKE_PROGRAM} -j${CHOMBO_BUILD_JOBS} lib
			# --- what gets built ---
			DIM=${DIM}
			USE_EB=TRUE          # embedded boundary code -- the whole point for VCell
			USE_MF=TRUE          # multifluid, requires USE_EB
			USE_HDF=TRUE
			USE_64=${_use64}
			MPI=FALSE
			DEBUG=FALSE
			OPT=TRUE
			# --- toolchain ---
			CXX=${_cxx_name}
			FC=${_fc_name}
			PERL=${CHOMBO_PERL_PROGRAM}
			# Chombo generates its dependency files through a csh one-liner; sh
			# runs the same pipeline and is always present.
			CSHELLCMD=/bin/sh\ -c
			# --- HDF5 ---
			HDFINCFLAGS=${_hdf_inc_flags}
			HDFLIBFLAGS=${CHOMBO_HDF5_LINK_FLAGS}
			# gfortran needs the C preprocessor run over the ChomboFortran output.
			fcppflags=-cpp
			WORKING_DIRECTORY "${CHOMBO_LIB_DIR}"
			COMMAND ${CMAKE_COMMAND}
			-DCHOMBO_LIB_DIR=${CHOMBO_LIB_DIR}
			-DDIM=${DIM}
			-DOUT_DIR=${_out}
			"-DEXPECTED_LIBS=${CHOMBO_LINK_ORDER}"
			-P "${PROJECT_SOURCE_DIR}/cmake/CollectChomboLibs.cmake"
			COMMAND ${CMAKE_COMMAND} -E touch "${_stamp}"
			VERBATIM)

	add_custom_target(chombo_${DIM}d DEPENDS ${_libs} ${_stamp})
	if (ARG_DEPENDS)
		add_dependencies(chombo_${DIM}d ${ARG_DEPENDS})
	endif ()

	set(CHOMBO_${DIM}D_INCLUDE_DIR "${_out}/include" PARENT_SCOPE)
	set(CHOMBO_${DIM}D_LIBRARIES "${_libs}" PARENT_SCOPE)
endfunction()
