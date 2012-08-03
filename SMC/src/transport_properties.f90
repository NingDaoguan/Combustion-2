module transport_properties

  use eglib_module
  use multifab_module
  use variables

  implicit none

  private

  public get_transport_properties

contains

  subroutine get_transport_properties(Q, mu, xi, lam, Ddiag)

    use multifab_module
    use variables

    type(multifab), intent(in   ) :: Q
    type(multifab), intent(inout) :: mu, xi, lam, Ddiag
 
    integer :: ng, n, dim, lo(Q%dim), hi(Q%dim)
    double precision, pointer, dimension(:,:,:,:) :: qp, mup, xip, lamp, dp

    dim = Q%dim
    ng = nghost(Q)

    do n=1,nboxes(Q)
       if ( remote(Q,n) ) cycle
       
       qp => dataptr(Q,n)
       mup => dataptr(mu,n)
       xip => dataptr(xi,n)
       lamp => dataptr(lam,n)
       dp => dataptr(Ddiag,n)

       lo = lwb(get_box(Q,n))
       hi = upb(get_box(Q,n))

       if (dim .ne. 3) then
          call bl_error("Only 3D is supported in get_transport_properties")
       else
          call get_trans_prop_3d(lo,hi,ng,qp,mup,xip,lamp,dp)
       end if

    end do

  end subroutine get_transport_properties
   
  subroutine get_trans_prop_3d(lo,hi,ng,q,mu,lam,xi,Ddiag)

    integer, intent(in) :: lo(3), hi(3), ng
    double precision,intent(in )::    q(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng,nprim)
    double precision,intent(out)::   mu(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::   xi(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::  lam(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng)
    double precision,intent(out)::Ddiag(lo(1)-ng:hi(1)+ng,lo(2)-ng:hi(2)+ng,lo(3)-ng:hi(3)+ng,nspecies)

    integer :: i, j, k, n, iwrk
    double precision :: rwrk, Tt, Pt, Wtm
    double precision, dimension(nspecies) :: Xt, Yt, Cpt
    double precision :: theta(nspecies), D(nspecies,nspecies)

    do k=lo(3)-ng,hi(3)+ng
    do j=lo(2)-ng,hi(2)+ng
    do i=lo(1)-ng,hi(1)+ng

       Tt = q(i,j,k,qtemp)
       Pt = q(i,j,k,qpres)
       Xt = q(i,j,k,qx1:qx1+nspecies-1)
       Yt = q(i,j,k,qy1:qy1+nspecies-1)

       CALL CKCPMS(Tt, iwrk, rwrk, Cpt)
       CALL CKMMWY(Yt, iwrk, rwrk, Wtm)

       CALL EGSPAR(Tt, Xt, Yt, Cpt, egwork, egiwork)

       CALL EGSE3(Tt, Yt, egwork, mu(i,j,k)) 
       CALL EGSK6(Tt, Yt, egwork, xi(i,j,k)) 
       CALL EGSLTDR3(Tt, Yt, Wtm, egwork, egiwork, &
            lam(i,j,k), theta, D)

       do n=1,nspecies
          Ddiag(i,j,k,n) = D(n,n)
       end do

    end do
    end do
    end do

  end subroutine get_trans_prop_3d

end module transport_properties
