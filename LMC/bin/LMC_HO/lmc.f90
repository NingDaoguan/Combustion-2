module lmc_module

   use div_u_module
   use cell_conversions_module
   use ghost_cells_module
   use advance_module
   use initial_conditions_module
   
   implicit none
   
   private
   public :: lmc
   
contains
   
   subroutine lmc()
      implicit none

      include 'spec.h'

      integer nsteps
      integer nsteps_taken
      integer at_nstep
      integer plot_int
      integer chk_int
      integer do_initial_projection
      integer num_divu_iters
      integer num_init_iters

!     cell-centered, 2 ghost cells
      real*8, allocatable ::  scal_new(:,:)
      real*8, allocatable ::  scal_old(:,:)
      real*8, allocatable ::  scal_avg(:,:)
      real*8, allocatable ::   scal_cc(:,:)

!     face values, no ghost cells
      real*8, allocatable :: vel(:)

!     cell-centered, no ghost cells
      real*8, allocatable ::   delta_chi(:)
      real*8, allocatable :: divu_old(:)
      real*8, allocatable :: divu_new(:)
      real*8, allocatable :: divu_avg(:)
      
      real*8, allocatable :: wdot(:,:)
      
      integer, allocatable :: bc(:)

      real*8, allocatable :: dx, dt

      real*8 problo,probhi
      real*8 time
      real*8 init_shrink
      real*8 stop_time
      real*8 fixed_dt
      real*8 Patm

      !integer divu_iter,init_iter

      character chkfile*(16)

      namelist /fortin/ nx,subcycling,nsteps,stop_time, &
                        problo,probhi,chkfile, &
                        plot_int, chk_int, &
                        init_shrink, flame_offset,&
                        fancy_predictor, dpdt_factor, &
                        Patm, coef_avg_harm, initial_S_type, &
                        recompute_S, probtype,&
                        misdc_iterMAX,&
                        do_initial_projection, num_divu_iters, &
                        num_init_iters,fixed_dt,&
                        V_in, nnodes, N2_comp, lim_rxns,&
                        LeEQ1, tranfile, TMIN_TRANS, Pr, Sc,&
                        max_vode_subcycles,&
                        min_vode_timestep, divu_ceiling_flag,&
                        divu_dt_factor, rho_divu_ceiling, unlim

!     Set defaults, change with namelist
      nx = 256
      subcycling = .false.
      nsteps = 10
      stop_time = 1.e4
      problo = 0.0
      probhi = 3.5
      chkfile = 'null'
      plot_int = 1
      chk_int = 1
      init_shrink = 0.1d0
      flame_offset = 0.d0
      fancy_predictor = 1
      initial_S_type = 1
      recompute_S = 0
      dpdt_factor = 0.d0
      Patm = 1.d0
      coef_avg_harm = 0
      misdc_iterMAX = 3
      do_initial_projection = 1
      num_divu_iters = 3
      num_init_iters = 2
      fixed_dt = -1.d0
      V_in = 1.d20
      nnodes = 3
      N2_comp = 0
      lim_rxns = 1
      LeEQ1 = 0
      tranfile = 'tran.asc.grimech30'
      TMIN_TRANS = 0.d0
      Pr = 0.7d0
      Sc = 0.7d0
      max_vode_subcycles = 15000
      min_vode_timestep = 1.e-19
      divu_ceiling_flag = 1
      divu_dt_factor    = 0.4d0
      rho_divu_ceiling  = 0.01
      unlim = 0
      probtype = 1
      verbose_vode = 0
      nchemdiag = 10
      
      open(9,file='probin',form='formatted',status='old')
      read(9,fortin)
      close(unit=9)

      if (probtype.ne.1 .and. probtype.ne.2) then
         print *,'Unknown probtype:',probtype,'  Must be 1 or 2' 
         stop
      endif

      write(*,fortin)

!     Initialize chem/tran database and nspec
      call initchem()

      Pcgs = Patm * P1ATM

!     defines Density, Temp, RhoH, RhoRT, FirstSpec, LastSpec, nscal,
!     u_bc, T_bc, Y_bc, h_bc, and rho_bc
      call probinit(problo,probhi)

!     cell-centered, 2 ghost cells
      allocate(scal_new(-2:nx+1,nscal))
      allocate(scal_old(-2:nx+1,nscal))
      allocate(scal_avg(-2:nx+1,nscal))
      allocate(scal_cc(-2:nx+1,nscal))

!     face-values, no ghost cells
      allocate(vel(0:nx))

!     cell-centered, no ghost cells
      allocate(delta_chi(0:nx-1))
      allocate( divu_old(0:nx-1))
      allocate( divu_new(0:nx-1))
      allocate( divu_avg(0:nx-1))
      
      allocate( wdot(0:nx-1, Nspec))
      
      allocate(bc(2))

      allocate(dx)
      allocate(dt)

!     only need to zero these so plotfile has sensible data
      divu_old = 0.d0
      divu_new = 0.d0
      vel = 0

!     must zero this or else RHS in mac project could be undefined
      delta_chi = 0.d0
      
!     initialize dx
      dx = (probhi-problo)/DBLE(nx)
      
!     initialize dt
      if (fixed_dt .le. 0.d0) then
         print*,'Error: must specify fixed_dt'
         stop
      else
         dt = fixed_dt
      end if

!     initialize boundary conditions
!     0=interior; 1=inflow; 2=outflow
      bc(1) = 1
      bc(2) = 2
      
      if ( chkfile .ne. 'null') then

         print *,'CHKFILE ',chkfile
         
         print *,'checkfile not yet implemented'
         stop
                  
      else
         
         time = 0.d0
         at_nstep = 1
         
         call load_initial_conditions(scal_avg, dx)
         scal_old = scal_avg
         
         call scal_avg_to_cc(scal_cc, scal_avg)
         call compute_production_rate(wdot, scal_cc, dx)
         
         call write_plt(vel,scal_old,divu_old, dx,99999,time)
      end if
         
      print *,' '      
      print *,'START ADVANCING THE SOLUTION '
      print *,' '            

1001  format('Advancing: starting time = ', e15.9,' with dt = ',e15.9)

!!!!!!!!!!!!!!!!!!!!!!!
!!! Advance in time !!!
!!!!!!!!!!!!!!!!!!!!!!!
      
      dodiff = .true.
      
      do nsteps_taken = at_nstep, nsteps
         if (time.ge.stop_time) exit
            dt = min(dt,stop_time-time)
            write(6,*)
            write(6,1001 )time,dt
            write(6,*)'STEP = ',nsteps_taken
         
            call advance(scal_old, scal_new, vel, divu_new, wdot, dt, dx)
            
            scal_old = scal_new
            
            time = time + dt
            
            print *,'steps taken = ', nsteps_taken
            print *,'steps       = ', nsteps
            
            if (mod(nsteps_taken,plot_int).eq.0 .or. nsteps_taken.eq.nsteps) then 
               call write_plt(vel,scal_new,divu_new,dx,nsteps_taken,time)
            endif
      enddo

      print *,' '      
      print *,'COMPLETED SUCCESSFULLY'
      print *,' '      
   end subroutine lmc

end module lmc_module
