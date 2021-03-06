module transport_properties

  use chemistry_module
  use multifab_module
  use variables_module

  use egz_module

  implicit none

  private

  public get_transport_properties

contains

  subroutine get_transport_properties(Q, mu, xi, lam, Ddiag, ng, ghostcells_only)

    type(multifab), intent(in   ) :: Q
    type(multifab), intent(inout) :: mu, xi, lam, Ddiag
    integer, intent(in), optional :: ng
    logical, intent(in), optional :: ghostcells_only
 
    integer :: ngwork
    logical :: lgco
    integer :: ngq, n, dm, lo(Q%dim), hi(Q%dim), wlo(Q%dim), whi(Q%dim)
    double precision, pointer, dimension(:,:,:,:) :: qp, mup, xip, lamp, dp

    dm = Q%dim
    ngq = nghost(Q)

    ngwork = ngq
    if (present(ng)) then
       ngwork = min(ngwork, ng)
    end if

    lgco = .false.
    if (present(ghostcells_only)) then
       lgco = ghostcells_only
    end if

    do n=1,nfabs(Q)
       
       qp => dataptr(Q,n)
       mup => dataptr(mu,n)
       xip => dataptr(xi,n)
       lamp => dataptr(lam,n)
       dp => dataptr(Ddiag,n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       wlo = lo - ngwork
       whi = hi + ngwork

       if (dm .ne. 3) then
          call bl_error("Only 3D is supported in get_transport_properties")
       else
          call get_trans_prop_3d(lo,hi,ngq,qp,mup,xip,lamp,dp,wlo,whi,lgco)
       end if

    end do

  end subroutine get_transport_properties

  subroutine get_trans_prop_3d(lo,hi,ng,q,mu,xi,lam,Ddiag,wlo,whi,gco)
    use probin_module, only : use_bulk_viscosity
    logical, intent(in) :: gco  ! ghost cells only
    integer, intent(in) :: lo(3), hi(3), ng, wlo(3), whi(3)
    double precision,intent(in )::    q(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng,nprim)
    double precision,intent(out)::   mu(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::   xi(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::  lam(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::Ddiag(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng,nspecies)

    integer :: i, j, k, n, np, qxn, iwrk, ii, jj, kk, iisize, jisize, kisize
    integer :: iindex(whi(1)-wlo(1)-hi(1)+lo(1))
    integer :: jindex(whi(2)-wlo(2)-hi(2)+lo(2))
    integer :: kindex(whi(3)-wlo(3)-hi(3)+lo(3))
    double precision :: rwrk, Cp(nspecies)
    double precision, allocatable :: L1Z(:), L2Z(:), DZ(:,:), XZ(:,:), CPZ(:,:), &
         TZ(:), EZ(:), KZ(:)

    if (.not. gco) then

       np = whi(1) - wlo(1) + 1

       !$omp parallel private(i,j,k,n,qxn,iwrk) &
       !$omp private(rwrk,Cp,L1Z,L2Z,DZ,XZ,CPZ)

       call egzini(np)
              
       allocate(L1Z(wlo(1):whi(1)))
       allocate(L2Z(wlo(1):whi(1)))

       allocate(DZ(wlo(1):whi(1),nspecies))
       allocate(XZ(wlo(1):whi(1),nspecies))
       allocate(CPZ(wlo(1):whi(1),nspecies))

       !$omp do collapse(2)
       do k=wlo(3),whi(3)
          do j=wlo(2),whi(2)

             do n=1,nspecies
                qxn = qx1+n-1
                do i=wlo(1),whi(1)
                   XZ(i,n) = q(i,j,k,qxn)
                end do
             end do

             if (use_bulk_viscosity) then
                do i=wlo(1),whi(1)
                   call ckcpms(q(i,j,k,qtemp), iwrk, rwrk, Cp)
                   CPZ(i,:) = Cp
                end do
             else
                CPZ = 0.d0
             end if

             call egzpar(q(wlo(1):whi(1),j,k,qtemp), XZ, CPZ)

             call egze3(q(wlo(1):whi(1),j,k,qtemp), mu(wlo(1):whi(1),j,k))

             if (use_bulk_viscosity) then
                CALL egzk3(q(wlo(1):whi(1),j,k,qtemp), xi(wlo(1):whi(1),j,k))
             else
                xi(wlo(1):whi(1),j,k) = 0.d0
             end if

             call egzl1( 1.d0, XZ, L1Z)
             call egzl1(-1.d0, XZ, L2Z)
             lam(wlo(1):whi(1),j,k) = 0.5d0*(L1Z+L2Z)

             call EGZVR1(q(wlo(1):whi(1),j,k,qtemp), DZ)
             do n=1,nspecies
                do i=wlo(1),whi(1)
                   Ddiag(i,j,k,n) = DZ(i,n)
                end do
             end do

          end do
       end do
       !$omp end do
       
       deallocate(L1Z, L2Z, DZ, XZ, CPZ)
       !$omp end parallel

    else ! ghost cells only 

       kisize = size(kindex)

       if (kisize > 0) then
          ! do k = wlo(3),lo(3)-1 & hi(3)+1,whi(3)
          ! do j = wlo(2), whi(2)
          ! do i = wlo(1), wlo(2)

          kk = 1
          do k=wlo(3),lo(3)-1
             kindex(kk) = k
             kk = kk+1
          end do
          do k=hi(3)+1,whi(3)
             kindex(kk) = k
             kk = kk+1
          end do

          np = whi(1) - wlo(1) + 1

          !$omp parallel private(i,j,k,kk,n,qxn,iwrk) &
          !$omp private(rwrk,Cp,L1Z,L2Z,DZ,XZ,CPZ)

          call egzini(np)
    
          allocate(L1Z(wlo(1):whi(1)))
          allocate(L2Z(wlo(1):whi(1)))

          allocate(DZ(wlo(1):whi(1),nspecies))
          allocate(XZ(wlo(1):whi(1),nspecies))
          allocate(CPZ(wlo(1):whi(1),nspecies))
       
          !$omp do collapse(2)
          do kk=1,kisize
             do j=wlo(2),whi(2)

                k = kindex(kk)

                do n=1,nspecies
                   qxn = qx1+n-1
                   do i=wlo(1),whi(1)
                      XZ(i,n) = q(i,j,k,qxn)
                   end do
                end do

                if (use_bulk_viscosity) then
                   do i=wlo(1),whi(1)
                      call ckcpms(q(i,j,k,qtemp), iwrk, rwrk, Cp)
                      CPZ(i,:) = Cp
                   end do
                else
                   CPZ = 0.d0
                end if
                
                call egzpar(q(wlo(1):whi(1),j,k,qtemp), XZ, CPZ)

                call egze3(q(wlo(1):whi(1),j,k,qtemp), mu(wlo(1):whi(1),j,k))

                if (use_bulk_viscosity) then
                   CALL egzk3(q(wlo(1):whi(1),j,k,qtemp), xi(wlo(1):whi(1),j,k))
                else
                   xi(wlo(1):whi(1),j,k) = 0.d0
                end if

                call egzl1( 1.d0, XZ, L1Z)
                call egzl1(-1.d0, XZ, L2Z)
                lam(wlo(1):whi(1),j,k) = 0.5d0*(L1Z+L2Z)

                call EGZVR1(q(wlo(1):whi(1),j,k,qtemp), DZ)
                do n=1,nspecies
                   do i=wlo(1),whi(1)
                      Ddiag(i,j,k,n) = DZ(i,n)
                   end do
                end do

             end do
          end do
          !$omp end do

          deallocate(L1Z, L2Z, DZ, XZ, CPZ)
          !$omp end parallel
       end if

       jisize = size(jindex)

       if (jisize > 0) then
          ! do k =  lo(3),  hi(3)
          ! do j = wlo(2),lo(2)-1 & hi(2)+2,whi(2)
          ! do i = wlo(1), wlo(2)

          jj = 1
          do j=wlo(2),lo(2)-1
             jindex(jj) = j
             jj = jj+1
          end do
          do j=hi(2)+1,whi(2)
             jindex(jj) = j
             jj = jj+1
          end do

          np = whi(1) - wlo(1) + 1

          !$omp parallel private(i,j,k,jj,n,qxn,iwrk) &
          !$omp private(rwrk,Cp,L1Z,L2Z,DZ,XZ,CPZ)

          call egzini(np)

          allocate(L1Z(wlo(1):whi(1)))
          allocate(L2Z(wlo(1):whi(1)))

          allocate(DZ(wlo(1):whi(1),nspecies))
          allocate(XZ(wlo(1):whi(1),nspecies))
          allocate(CPZ(wlo(1):whi(1),nspecies))
    
          !$omp do collapse(2)
          do k=lo(3),hi(3)
             do jj=1,jisize

                j = jindex(jj)

                do n=1,nspecies
                   qxn = qx1+n-1
                   do i=wlo(1),whi(1)
                      XZ(i,n) = q(i,j,k,qxn)
                   end do
                end do
                
                if (use_bulk_viscosity) then
                   do i=wlo(1),whi(1)
                      call ckcpms(q(i,j,k,qtemp), iwrk, rwrk, Cp)
                      CPZ(i,:) = Cp
                   end do
                else
                   CPZ = 0.d0
                end if
                
                call egzpar(q(wlo(1):whi(1),j,k,qtemp), XZ, CPZ)

                call egze3(q(wlo(1):whi(1),j,k,qtemp), mu(wlo(1):whi(1),j,k))

                if (use_bulk_viscosity) then
                   CALL egzk3(q(wlo(1):whi(1),j,k,qtemp), xi(wlo(1):whi(1),j,k))
                else
                   xi(wlo(1):whi(1),j,k) = 0.d0
                end if

                call egzl1( 1.d0, XZ, L1Z)
                call egzl1(-1.d0, XZ, L2Z)
                lam(wlo(1):whi(1),j,k) = 0.5d0*(L1Z+L2Z)

                call EGZVR1(q(wlo(1):whi(1),j,k,qtemp), DZ)
                do n=1,nspecies
                   do i=wlo(1),whi(1)
                      Ddiag(i,j,k,n) = DZ(i,n)
                   end do
                end do
                
             end do
          end do
          !$omp end do

          deallocate(L1Z, L2Z, DZ, XZ, CPZ)
          !$omp end parallel
       end if
       
       iisize = size(iindex)

       if (iisize > 0) then
          ! do k = lo(3), hi(3)
          ! do j = lo(2), hi(2)
          ! do i = wlo(1),lo(1)-1 & hi(1)+1,whi(1)

          ii = 1
          do i=wlo(1),lo(1)-1
             iindex(ii) = i
             ii = ii+1
          end do
          do i=hi(1)+1,whi(1)
             iindex(ii) = i
             ii = ii+1
          end do
          
          np = iisize

          !$omp parallel private(i,j,k,ii,n,qxn,iwrk) &
          !$omp private(rwrk,Cp,L1Z,L2Z,DZ,XZ,CPZ,TZ,EZ,KZ)

          call egzini(np)
    
          allocate(TZ(np))
          allocate(EZ(np))
          allocate(KZ(np))
          allocate(L1Z(np))
          allocate(L2Z(np))
          allocate(DZ(np,nspecies))
          allocate(XZ(np,nspecies))
          allocate(CPZ(np,nspecies))
        
          !$omp do collapse(2)
          do k=lo(3),hi(3)
             do j=lo(2),hi(2)

                do n=1,nspecies
                   qxn = qx1+n-1
                   do ii=1,np
                      i = iindex(ii)
                      XZ(ii,n) = q(i,j,k,qxn)
                   end do
                end do

                if (use_bulk_viscosity) then
                   do ii=1,np
                      i = iindex(ii)
                      TZ(ii) = q(i,j,k,qtemp)
                      call ckcpms(TZ(ii), iwrk, rwrk, Cp)
                      CPZ(ii,:) = Cp
                   end do
                else
                   CPZ = 0.d0
                end if

                call egzpar(TZ, XZ, CPZ)

                call egze3(TZ, EZ)
                               
                if (use_bulk_viscosity) then
                   CALL egzk3(TZ, KZ)
                else
                   KZ = 0.d0
                end if

                call egzl1( 1.d0, XZ, L1Z)
                call egzl1(-1.d0, XZ, L2Z)

                do ii=1,np
                   i = iindex(ii)
                   mu(i,j,k) = EZ(ii)
                   xi(i,j,k) = KZ(ii)
                   lam(i,j,k) = 0.5d0*(L1Z(ii)+L2Z(ii))
                end do

                call EGZVR1(TZ, DZ)
                do n=1,nspecies
                   do ii=1,np
                      i = iindex(ii)
                      Ddiag(i,j,k,n) = DZ(ii,n)
                   end do
                end do
 
             end do
          end do
          !$omp end do

          deallocate(TZ, EZ, KZ, L1Z, L2Z, DZ, XZ, CPZ)
          !$omp end parallel
       end if

    end if

  end subroutine get_trans_prop_3d

end module transport_properties
