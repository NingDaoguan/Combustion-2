EXEname := lmc.exe

#
# Choose pmf file
#
#pmf_source := ../../../Chemistry/data/gri/PMFs/gri30_070.f
pmf_source := ../../../Chemistry/data/chem-H/PMFs/chemHSoln_seed_0.00.f
#pmf_source := ../../../Chemistry/data/Lu/PMFs/LuDME_0700.f
#
# Choose reaction mechanism
# Use GRI30 for pmf_source := gri30_070.f
# Use CHEMH for pmf_source := chemHSoln_seed_0.00.f
# Use LUDME for pmf_source := LuDME_0700.f
#
#REACTION_MECHANISM=GRI30
REACTION_MECHANISM=CHEMH
#REACTION_MECHANISM=LUDME

fCOMP := gfortran -g -fbounds-check -w -ffixed-line-length-none
f90COMP := gfortran -g -fbounds-check -Wall -Wno-unused-dummy-argument -ffixed-line-length-none
CCOMP := g++ -g -O0 -fno-exceptions -Wall -Wno-sign-compare -DBL_FORT_USE_UNDERSCORE
cCOMP := gcc -g -O0 -std=c99 -fno-exceptions -Wall -Wno-sign-compare -DBL_FORT_USE_UNDERSCORE
XTRALIBS :=  -lm -lgfortran

ifeq ($(REACTION_MECHANISM),GRI30)
  mech_source += ../../../Chemistry/data/gri/grimech30.c
endif
ifeq ($(REACTION_MECHANISM),CHEMH)
  mech_source += ../../../Chemistry/data/chem-H/chem-H.c
endif
ifeq ($(REACTION_MECHANISM),LUDME)
  mech_source += ../../../Chemistry/data/Lu/LuDME.c
endif

chem_sources := ../../../Chemistry/src/vode.f \
                ../../../Chemistry/src/EGini.f \
                ../../../Chemistry/src/EGSlib.f \
                ../../../Chemistry/src/math_d.f

pmf_object := $(pmf_source:%.f=%.o)
mech_object := $(mech_source:%.c=%.o)
chem_objects := $(chem_sources:%.f=%.o)

f_sources += ${chem_sources} ${pmf_source}
f90_sources += test.f90

#f_includes += spec.h
C_includedirs += -I../../../Chemistry/src

C_objects := $(C_sources:%.cpp=%.o)
f_objects := $(f_sources:%.f=%.o)
f90_objects := $(f90_sources:%.f90=%.o)

${EXEname}: ${f_objects} ${f90_objects} ${mech_object} ${C_objects} ${f_includes}
	${CCOMP} -o ${EXEname} ${f_objects} ${f90_objects} ${mech_object} ${C_objects} ${XTRALIBS}

clean:
	\rm -rf ${EXEname} ${f_objects} ${f90_objects} ${C_objects} Linkeg

%.o: %.cpp
	${CCOMP} ${C_includedirs} -c $^ -o $*.o

%.o: %.c
	${cCOMP} ${C_includedirs} -c $^ -o $*.o

%.o: %.f90
	${f90COMP} -c $^ -o $*.o
	
%.o: %.f
	${fCOMP} -c $^ -o $*.o


MySrcDirs += .
vpath %.cpp $(MySrcDirs)
vpath %.c   $(MySrcDirs)
vpath %.h   $(MySrcDirs)
vpath %.f   $(MySrcDirs)
vpath %.f90 $(MySrcDirs)
