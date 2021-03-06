
  subroutine outlet_xlo_3d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(3), hi(3), ngq, ngc, dlo(3), dhi(3)
    double precision,intent(in   )::dx(3)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,-ngc+lo(3):hi(3)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2),lo(3):hi(3))

    integer :: i,j,k,n
    double precision :: dxinv(3)
    double precision :: rho, u, v, w, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, dvdn, dwdn, drhodn, dYdn(nspecies)
    double precision :: L(5+nspecies), Ltr(5+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_w, d_p
    double precision :: hcal, cpWT, gam1

    double precision, dimension(lo(2):hi(2),lo(3):hi(3)) :: &
         dpdy, dpdz, dudy, dudz, dvdy, dwdz
    
    i = lo(1)

    do n=1,3
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_3d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dpdz,dudy,dudz,dvdy,dwdz)

    !$omp parallel do private(j,k,n,rho,u,v,w,T,pres,Y,h,rhoE) &
    !$omp private(dpdn, dudn,dvdn,dwdn, drhodn, dYdn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_w, d_p, hcal, cpWT, gam1)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          
          rho  = q  (i,j,k,qrho)
          u    = q  (i,j,k,qu)
          v    = q  (i,j,k,qv)
          w    = q  (i,j,k,qw)
          pres = q  (i,j,k,qpres)
          T    = q  (i,j,k,qtemp)
          Y    = q  (i,j,k,qy1:qy1+nspecies-1)
          h    = q  (i,j,k,qh1:qh1+nspecies-1)
          rhoE = con(i,j,k,iene)
          
          drhodn     = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qrho))
          dudn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qu))
          dvdn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qv))
          dwdn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qw))
          dpdn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qpres))
          do n=1,nspecies
             dYdn(n) = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qy1+n-1))
          end do
          
          ! Simple 1D LODI 
          L(1) = (u-aux(ics,j,k))*0.5d0*(dpdn-rho*aux(ics,j,k)*dudn)
          L(2) = u*(drhodn-dpdn/aux(ics,j,k)**2)
          L(3) = u*dvdn
          L(4) = u*dwdn
          L(5) = sigma*aux(ics,j,k)*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*(pres-Pinfty)
          L(6:) = u*dYdn
          
          ! multi-D effects
          Ltr(5) = -0.5d0*(v*dpdy(j,k)+w*dpdz(j,k) &
               + aux(igamma,j,k)*pres*(dvdy(j,k)+dwdz(j,k)) &
               + rho*aux(ics,j,k)*(v*dudy(j,k)+w*dudz(j,k)))
          L(5) = L(5) + min(0.99d0, (1.0d0-abs(u)/aux(ics,j,k))) * Ltr(5) 
          
          ! viscous and reaction effects
          d_u = fd(i,j,k,imx) / rho
          d_v = fd(i,j,k,imy) / rho
          d_w = fd(i,j,k,imz) / rho
           
          S_p = 0.d0
          d_p = fd(i,j,k,iene) - (d_u*con(i,j,k,imx)+d_v*con(i,j,k,imy)+d_w*con(i,j,k,imz))
          cpWT = aux(icp,j,k)*aux(iWbar,j,k)*T
          gam1 = aux(igamma,j,k) - 1.d0
          do n=1,nspecies
             hcal = h(n) - cpWT*inv_mwt(n)
             S_p    = S_p - hcal*aux(iwdot1+n-1,j,k)
             S_Y(n) = aux(iwdot1+n-1,j,k) / rho
             d_p    = d_p - hcal*fd(i,j,k,iry1+n-1)
          end do
          S_p = gam1 * S_p
          d_p = gam1 * d_p 
          
          L(5) = L(5) + 0.5d0*(S_p + d_p + rho*aux(ics,j,k)*d_u)
          
          if (u > 0.d0) then
             L(2) = -S_p/aux(ics,j,k)**2
             L(3) = 0.d0
             L(4) = 0.d0
             L(6:) = S_Y      
             
             L(5) = 0.5d0*(S_p + d_p + rho*aux(ics,j,k)*d_u) + Ltr(5) &
                  + outlet_eta*aux(igamma,j,k)*pres*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*u
          end if
          
          call LtoLHS_3d(1, L, lhs, aux(:,j,k), rho, u, v, w, T, Y, h, rhoE)
          
          rhs(i,j,k,:) = rhs(i,j,k,:) - lhs
          
       end do
    end do
    !$omp end parallel do

  end subroutine outlet_xlo_3d


  subroutine inlet_xlo_3d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,qin,dlo,dhi)
    integer, intent(in) :: lo(3), hi(3), ngq, ngc, dlo(3), dhi(3)
    double precision,intent(in   )::dx(3)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,-ngc+lo(3):hi(3)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2),lo(3):hi(3))
    double precision,intent(in   )::qin(nqin,lo(2):hi(2),lo(3):hi(3))

    integer :: i,j,k,n
    double precision :: dxinv(3)
    double precision :: rho, u, v, w, T, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn
    double precision :: L(5+nspecies), Ltr(5+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_w, d_p, d_Y(nspecies)
    double precision :: hcal, cpWT, gam1, cs2

    double precision, dimension(lo(2):hi(2),lo(3):hi(3)) :: &
         drhody, drhodz, dudy, dudz, dvdy, dvdz, dwdy, dwdz, dpdy, dpdz
    double precision, dimension(nspecies,lo(2):hi(2),lo(3):hi(3)) :: dYdy, dYdz
    
    i = lo(1)

    do n=1,3
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_3d (i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dpdz,dudy,dudz,dvdy,dwdz)
    call comp_trans_deriv_x2_3d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,drhody,drhodz,dvdz,dwdy,dYdy,dYdz)

    !$omp parallel do private(j,k,n,rho,u,v,w,T,Y,h,rhoE) &
    !$omp private(dpdn, dudn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_w, d_p, d_Y, hcal, cpWT, gam1, cs2)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          
          rho  = q  (i,j,k,qrho)
          u    = q  (i,j,k,qu)
          v    = q  (i,j,k,qv)
          w    = q  (i,j,k,qw)
          T    = q  (i,j,k,qtemp)
          Y    = q  (i,j,k,qy1:qy1+nspecies-1)
          h    = q  (i,j,k,qh1:qh1+nspecies-1)
          rhoE = con(i,j,k,iene)
          
          dudn = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qu))
          dpdn = dxinv(1)*first_deriv_rb(q(i:i+3,j,k,qpres))
          
          cs2 = aux(ics,j,k)**2

          ! Simple 1D LODI 
          L(1) = (u-aux(ics,j,k))*0.5d0*(dpdn-rho*aux(ics,j,k)*dudn)
          L(2) = -inlet_eta*Ru*rho*(T-qin(iTin,j,k)) & 
               / (Lxdomain*aux(ics,j,k)*aux(iWbar,j,k))
          L(3) = inlet_eta*aux(ics,j,k)/Lxdomain*(v-qin(ivin,j,k))
          L(4) = inlet_eta*aux(ics,j,k)/Lxdomain*(w-qin(iwin,j,k))
          L(5) = inlet_eta*rho*cs2*(1.d0-Ma2_xlo)/(2.d0*Lxdomain) &
               * (u-qin(iuin,j,k))
          L(6:) = inlet_eta*aux(ics,j,k)/Lxdomain*(Y-qin(iYin1:,j,k))
          
          ! multi-D effects
          Ltr(2) = -v*(drhody(j,k) - dpdy(j,k)/cs2) &
               &  - w*(drhodz(j,k) - dpdz(j,k)/cs2)
          Ltr(3) = -(v*dvdy(j,k) + w*dvdz(j,k) + dpdy(j,k)/rho)
          Ltr(4) = -(v*dwdy(j,k) + w*dwdz(j,k) + dpdz(j,k)/rho)
          Ltr(5) = -0.5*((v*dpdy(j,k)+w*dpdz(j,k))     &
               + rho*cs2*(dvdy(j,k)+dwdz(j,k))     &
               + rho*aux(ics,j,k)*(v*dudy(j,k)+w*dudz(j,k)))
          Ltr(6:)= -(v*dYdy(:,j,k)+w*dYdz(:,j,k))

          L(2:) = L(2:) + Ltr(2:)

          ! viscous and reaction effects
          d_u = fd(i,j,k,imx) / rho
          d_v = fd(i,j,k,imy) / rho
          d_w = fd(i,j,k,imz) / rho
          
          S_p = 0.d0
          d_p = fd(i,j,k,iene) - (d_u*con(i,j,k,imx)+d_v*con(i,j,k,imy)+d_w*con(i,j,k,imz))
          cpWT = aux(icp,j,k)*aux(iWbar,j,k)*T
          gam1 = aux(igamma,j,k) - 1.d0
          do n=1,nspecies
             hcal = h(n) - cpWT*inv_mwt(n)
             S_p    = S_p - hcal*aux(iwdot1+n-1,j,k)
             S_Y(n) = aux(iwdot1+n-1,j,k) / rho
             d_p    = d_p - hcal*fd(i,j,k,iry1+n-1)
             d_Y(n) = fd(i,j,k,iry1+n-1) / rho
          end do
          S_p = gam1 * S_p
          d_p = gam1 * d_p 

          L(2)  = L(2)  - (d_p + S_p) / cs2
          L(3)  = L(3)  + d_v
          L(4)  = L(4)  + d_w
          L(5)  = L(5)  + 0.5d0*(S_p + d_p + rho*aux(ics,j,k)*d_u)
          L(6:) = L(6:) + S_Y + d_Y

          call LtoLHS_3d(1, L, lhs, aux(:,j,k), rho, u, v, w, T, Y, h, rhoE)
          
          rhs(i,j,k,:) = rhs(i,j,k,:) - lhs
          
       end do
    end do
    !$omp end parallel do

  end subroutine inlet_xlo_3d


  subroutine outlet_xhi_3d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(3), hi(3), ngq, ngc, dlo(3), dhi(3)
    double precision,intent(in   )::dx(3)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,-ngc+lo(3):hi(3)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2),lo(3):hi(3))

    integer :: i,j,k,n
    double precision :: dxinv(3)
    double precision :: rho, u, v, w, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, dvdn, dwdn, drhodn, dYdn(nspecies)
    double precision :: L(5+nspecies), Ltr(5+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_w, d_p
    double precision :: hcal, cpWT, gam1

    double precision, dimension(lo(2):hi(2),lo(3):hi(3)) :: &
         dpdy, dpdz, dudy, dudz, dvdy, dwdz
    
    i = hi(1)

    do n=1,3
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_3d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dpdz,dudy,dudz,dvdy,dwdz)

    !$omp parallel do private(j,k,n,rho,u,v,w,T,pres,Y,h,rhoE) &
    !$omp private(dpdn, dudn, dvdn, dwdn, drhodn, dYdn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_w, d_p, hcal, cpWT, gam1)
    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          
          rho  = q  (i,j,k,qrho)
          u    = q  (i,j,k,qu)
          v    = q  (i,j,k,qv)
          w    = q  (i,j,k,qw)
          pres = q  (i,j,k,qpres)
          T    = q  (i,j,k,qtemp)
          Y    = q  (i,j,k,qy1:qy1+nspecies-1)
          h    = q  (i,j,k,qh1:qh1+nspecies-1)
          rhoE = con(i,j,k,iene)
          
          drhodn     = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qrho))
          dudn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qu))
          dvdn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qv))
          dwdn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qw))
          dpdn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qpres))
          do n=1,nspecies
             dYdn(n) = dxinv(1)*first_deriv_lb(q(i-3:i,j,k,qy1+n-1))
          end do
          
          ! Simple 1D LODI 
          L(1) = sigma*aux(ics,j,k)*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*(pres-Pinfty)
          L(2) = u*(drhodn-dpdn/aux(ics,j,k)**2)
          L(3) = u*dvdn
          L(4) = u*dwdn
          L(5) = (u+aux(ics,j,k))*0.5d0*(dpdn+rho*aux(ics,j,k)*dudn)
          L(6:) = u*dYdn
          
          ! multi-D effects
          Ltr(1) = -0.5d0*(v*dpdy(j,k)+w*dpdz(j,k) &
               + aux(igamma,j,k)*pres*(dvdy(j,k)+dwdz(j,k)) &
               - rho*aux(ics,j,k)*(v*dudy(j,k)+w*dudz(j,k)))
          L(1) = L(1) + min(0.99d0, (1.0d0-abs(u)/aux(ics,j,k))) * Ltr(1)
          
          ! viscous and reaction effects
          d_u = fd(i,j,k,imx) / rho
          d_v = fd(i,j,k,imy) / rho
          d_w = fd(i,j,k,imz) / rho

          S_p = 0.d0
          d_p = fd(i,j,k,iene) - (d_u*con(i,j,k,imx)+d_v*con(i,j,k,imy)+d_w*con(i,j,k,imz))
          cpWT = aux(icp,j,k)*aux(iWbar,j,k)*T
          gam1 = aux(igamma,j,k) - 1.d0
          do n=1,nspecies
             hcal = h(n) - cpWT*inv_mwt(n)
             S_p    = S_p - hcal*aux(iwdot1+n-1,j,k)
             S_Y(n) = aux(iwdot1+n-1,j,k) / rho
             d_p    = d_p - hcal*fd(i,j,k,iry1+n-1)
          end do
          S_p = gam1 * S_p
          d_p = gam1 * d_p 

          L(1) = L(1) + 0.5d0*(S_p + d_p - rho*aux(ics,j,k)*d_u)
          
          if (u < 0.d0) then
             L(2) = -S_p/aux(ics,j,k)**2
             L(3) = 0.d0
             L(4) = 0.d0
             L(6:) = S_Y      
             
             L(1) = 0.5d0*(S_p + d_p - rho*aux(ics,j,k)*d_u) + Ltr(1) &
                  - outlet_eta*aux(igamma,j,k)*pres*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*u
          end if
          
          call LtoLHS_3d(1, L, lhs, aux(:,j,k), rho, u, v, w, T, Y, h, rhoE)
          
          rhs(i,j,k,:) = rhs(i,j,k,:) - lhs
          
       end do
    end do
    !$omp end parallel do
    
  end subroutine outlet_xhi_3d


!   subroutine inlet_xhi(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,qin,dlo,dhi)
!     integer, intent(in) :: lo(3), hi(3), ngq, ngc, dlo(3), dhi(3)
!     double precision,intent(in   )::dx(3)
!     double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
!     double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,-ngc+lo(3):hi(3)+ngc,ncons)
!     double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
!     double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3),ncons)
!     double precision,intent(in   )::aux(naux,lo(2):hi(2),lo(3):hi(3))
!     double precision,intent(in   )::qin(nqin,lo(2):hi(2),lo(3):hi(3))

!     ! integer :: i,j,k,n
!     ! double precision :: dxinv(3)
!     ! double precision :: rho, u, v, w, T, pres, Y(nspecies), h(nspecies), rhoE
!     ! double precision :: dpdn, dudn(3), drhodn, dYdn(nspecies)
!     ! double precision :: L(5+nspecies), Ltr(5+nspecies), lhs(ncons)
!     ! double precision :: S_p, S_Y(nspecies), d_u, d_v, d_w, d_p
!     ! double precision :: hcal, cpWT, gam1, cs2

!     ! double precision, dimension(lo(2):hi(2),lo(3):hi(3)) :: &
!     !      drhody, drhodz, dudy, dudz, dvdy, dvdz, dwdy, dwdz, dpdy, dpdz
!     ! double precision, dimension(nspecies,lo(2):hi(2),lo(3):hi(3)) :: dYdy, dYdz

!     call bl_error("inlet_xhi not implemented")

!   end subroutine inlet_xhi


  subroutine comp_trans_deriv_x_3d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dpdz,dudy,dudz,dvdy,dwdz)
    integer, intent(in) :: i, lo(3), hi(3), ngq,dlo(3),dhi(3)
    double precision, intent(in) :: dxinv(3)
    double precision, intent(in) :: Q(-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
    double precision, intent(out):: dpdy(lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dpdz(lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dudy(lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dudz(lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dvdy(lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dwdz(lo(2):hi(2),lo(3):hi(3))

    integer :: j, k, slo(3), shi(3)

    slo = dlo + stencil_ng
    shi = dhi - stencil_ng

    !$omp parallel private(j,k)

    ! d()/dy
    !$omp do
    do k=lo(3),hi(3)
       
       do j=slo(2),shi(2)
          dudy(j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qpres))
       end do

       ! lo-y boundary
       if (dlo(2) .eq. lo(2)) then
          j = lo(2)
          ! use completely right-biased stencil
          dudy(j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qpres))          

          j = lo(2)+1
          ! use 3rd-order slightly right-biased stencil
          dudy(j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qpres))          

          j = lo(2)+2
          ! use 4th-order stencil
          dudy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qpres))          

          j = lo(2)+3
          ! use 6th-order stencil
          dudy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qpres))          
       end if

       ! hi-y boundary
       if (dhi(2) .eq. hi(2)) then
          j = hi(2)-3
          ! use 6th-order stencil
          dudy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qpres))          

          j = hi(2)-2
          ! use 4th-order stencil
          dudy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qpres))          
          
          j = hi(2)-1
          ! use 3rd-order slightly left-biased stencil
          dudy(j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qpres))          

          j = hi(2)
          ! use completely left-biased stencil
          dudy(j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qu))
          dvdy(j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qv))
          dpdy(j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qpres))  
       end if

    end do
    !$omp end do nowait

    ! d()/dz
    !$omp do
    do k=slo(3),shi(3)
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qpres))
       end do
    end do
    !$omp end do nowait

    ! lo-z boundary
    if (dlo(3) .eq. lo(3)) then
       k = lo(3)
       ! use completely right-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qpres))
       end do
       !$omp end do nowait

       k = lo(3)+1
       ! use 3rd-order slightly right-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qpres))
       end do
       !$omp end do nowait

       k = lo(3)+2
       ! use 4th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qpres))
       end do
       !$omp end do nowait

       k = lo(3)+3
       ! use 6th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qpres))
       end do
       !$omp end do nowait
    end if
    
    ! hi-z boundary
    if (dhi(3) .eq. hi(3)) then
       k = hi(3)-3
       ! use 6th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qpres))
       end do
       !$omp end do nowait

       k = hi(3)-2
       ! use 4th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qpres))
       end do
       !$omp end do nowait

       k = hi(3)-1
       ! use 3rd-order slightly left-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qpres))
       end do
       !$omp end do nowait

       k = hi(3)
       ! use completely left-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dudz(j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qu))
          dwdz(j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qw))
          dpdz(j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qpres))
       end do
       !$omp end do nowait
    end if

    !$omp end parallel

  end subroutine comp_trans_deriv_x_3d


  subroutine comp_trans_deriv_x2_3d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dddy,dddz,dvdz,dwdy,dYdy,dYdz)
    integer, intent(in) :: i, lo(3), hi(3), ngq,dlo(3),dhi(3)
    double precision, intent(in) :: dxinv(3)
    double precision, intent(in) :: Q(-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,-ngq+lo(3):hi(3)+ngq,nprim)
    double precision, intent(out):: dddy(         lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dddz(         lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dvdz(         lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dwdy(         lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dYdy(nspecies,lo(2):hi(2),lo(3):hi(3))
    double precision, intent(out):: dYdz(nspecies,lo(2):hi(2),lo(3):hi(3))

    integer :: j, k, n, slo(3), shi(3)

    slo = dlo + stencil_ng
    shi = dhi - stencil_ng

    !$omp parallel private(j,k,n)

    ! d()/dy
    !$omp do
    do k=lo(3),hi(3)
       
       do j=slo(2),shi(2)
          dddy     (j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,k,qy1+n-1))
          end do
       end do

       ! lo-y boundary
       if (dlo(2) .eq. lo(2)) then
          j = lo(2)
          ! use completely right-biased stencil
          dddy     (j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_rb(q(i,j:j+3,k,qy1+n-1))          
          end do

          j = lo(2)+1
          ! use 3rd-order slightly right-biased stencil
          dddy     (j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,k,qy1+n-1))          
          end do

          j = lo(2)+2
          ! use 4th-order stencil
          dddy     (j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qy1+n-1))          
          end do

          j = lo(2)+3
          ! use 6th-order stencil
          dddy     (j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qy1+n-1))          
          end do
       end if

       ! hi-y boundary
       if (dhi(2) .eq. hi(2)) then
          j = hi(2)-3
          ! use 6th-order stencil
          dddy     (j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,k,qy1+n-1))          
          end do

          j = hi(2)-2
          ! use 4th-order stencil
          dddy     (j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,k,qy1+n-1))          
          end do
          
          j = hi(2)-1
          ! use 3rd-order slightly left-biased stencil
          dddy     (j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,k,qy1+n-1)) 
          end do

          j = hi(2)
          ! use completely left-biased stencil
          dddy     (j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qrho))
          dwdy     (j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qw))
          do n=1,nspecies
             dYdy(n,j,k) = dxinv(2)*first_deriv_lb(q(i,j-3:j,k,qy1+n-1))  
          end do
       end if

    end do
    !$omp end do nowait

    ! d()/dz
    !$omp do
    do k=slo(3),shi(3)
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_8(q(i,j,k-4:k+4,qy1+n-1))
          end do
       end do
    end do
    !$omp end do nowait

    ! lo-z boundary
    if (dlo(3) .eq. lo(3)) then
       k = lo(3)
       ! use completely right-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_rb(q(i,j,k:k+3,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = lo(3)+1
       ! use 3rd-order slightly right-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_r3(q(i,j,k-1:k+2,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = lo(3)+2
       ! use 4th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = lo(3)+3
       ! use 6th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qy1+n-1))
          end do
       end do
       !$omp end do nowait
    end if
    
    ! hi-z boundary
    if (dhi(3) .eq. hi(3)) then
       k = hi(3)-3
       ! use 6th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_6(q(i,j,k-3:k+3,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = hi(3)-2
       ! use 4th-order stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_4(q(i,j,k-2:k+2,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = hi(3)-1
       ! use 3rd-order slightly left-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_l3(q(i,j,k-2:k+1,qy1+n-1))
          end do
       end do
       !$omp end do nowait

       k = hi(3)
       ! use completely left-biased stencil
       !$omp do
       do j=lo(2),hi(2)
          dddz     (j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qrho))
          dvdz     (j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qv))
          do n=1,nspecies
             dYdz(n,j,k) = dxinv(3)*first_deriv_lb(q(i,j,k-3:k,qy1+n-1))
          end do
       end do
       !$omp end do nowait
    end if

    !$omp end parallel

  end subroutine comp_trans_deriv_x2_3d


! ----------------- 2D routine --------------------------


  subroutine outlet_xlo_2d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(2), hi(2), ngq, ngc, dlo(2), dhi(2)
    double precision,intent(in   )::dx(2)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2))

    integer :: i,j,n
    double precision :: dxinv(2)
    double precision :: rho, u, v, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, dvdn, drhodn, dYdn(nspecies)
    double precision :: L(4+nspecies), Ltr(4+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_p
    double precision :: hcal, cpWT, gam1

    double precision, dimension(lo(2):hi(2)) :: dpdy, dudy, dvdy
    
    i = lo(1)

    do n=1,2
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_2d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dudy,dvdy)

    !$omp parallel do private(j,n,rho,u,v,T,pres,Y,h,rhoE) &
    !$omp private(dpdn, dudn,dvdn, drhodn, dYdn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_p, hcal, cpWT, gam1)
    do j=lo(2),hi(2)
          
       rho  = q  (i,j,qrho)
       u    = q  (i,j,qu)
       v    = q  (i,j,qv)
       pres = q  (i,j,qpres)
       T    = q  (i,j,qtemp)
       Y    = q  (i,j,qy1:qy1+nspecies-1)
       h    = q  (i,j,qh1:qh1+nspecies-1)
       rhoE = con(i,j,iene)
          
       drhodn     = dxinv(1)*first_deriv_rb(q(i:i+3,j,qrho))
       dudn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,qu))
       dvdn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,qv))
       dpdn       = dxinv(1)*first_deriv_rb(q(i:i+3,j,qpres))
       do n=1,nspecies
          dYdn(n) = dxinv(1)*first_deriv_rb(q(i:i+3,j,qy1+n-1))
       end do
       
       ! Simple 1D LODI 
       L(1) = (u-aux(ics,j))*0.5d0*(dpdn-rho*aux(ics,j)*dudn)
       L(2) = u*(drhodn-dpdn/aux(ics,j)**2)
       L(3) = u*dvdn
       L(4) = sigma*aux(ics,j)*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*(pres-Pinfty)
       L(5:) = u*dYdn
          
       ! multi-D effects
       Ltr(4) = -0.5d0*(v*dpdy(j) &
               + aux(igamma,j)*pres*dvdy(j) &
               + rho*aux(ics,j)*v*dudy(j))
       L(4) = L(4) + min(0.99d0, (1.0d0-abs(u)/aux(ics,j))) * Ltr(4) 
          
       ! viscous and reaction effects
       d_u = fd(i,j,imx) / rho
       d_v = fd(i,j,imy) / rho
       
       S_p = 0.d0
       d_p = fd(i,j,iene) - (d_u*con(i,j,imx)+d_v*con(i,j,imy))
       cpWT = aux(icp,j)*aux(iWbar,j)*T
       gam1 = aux(igamma,j) - 1.d0
       do n=1,nspecies
          hcal = h(n) - cpWT*inv_mwt(n)
          S_p    = S_p - hcal*aux(iwdot1+n-1,j)
          S_Y(n) = aux(iwdot1+n-1,j) / rho
          d_p    = d_p - hcal*fd(i,j,iry1+n-1)
       end do
       S_p = gam1 * S_p
       d_p = gam1 * d_p 
       
       L(4) = L(4) + 0.5d0*(S_p + d_p + rho*aux(ics,j)*d_u)
          
       if (u > 0.d0) then
          L(2) = -S_p/aux(ics,j)**2
          L(3) = 0.d0
          L(5:) = S_Y      
             
          L(4) = 0.5d0*(S_p + d_p + rho*aux(ics,j)*d_u) + Ltr(4) &
               + outlet_eta*aux(igamma,j)*pres*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*u
       end if
          
       call LtoLHS_2d(1, L, lhs, aux(:,j), rho, u, v, T, Y, h, rhoE)
          
       rhs(i,j,:) = rhs(i,j,:) - lhs
       
    end do
    !$omp end parallel do

  end subroutine outlet_xlo_2d


  subroutine inlet_xlo_2d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,qin,dlo,dhi)
    integer, intent(in) :: lo(2), hi(2), ngq, ngc, dlo(2), dhi(2)
    double precision,intent(in   )::dx(2)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2))
    double precision,intent(in   )::qin(nqin,lo(2):hi(2))

    integer :: i,j,n
    double precision :: dxinv(2)
    double precision :: rho, u, v, T, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn
    double precision :: L(4+nspecies), Ltr(4+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_p, d_Y(nspecies)
    double precision :: hcal, cpWT, gam1, cs2

    double precision, dimension(lo(2):hi(2)) :: drhody, dudy, dvdy, dpdy
    double precision, dimension(nspecies,lo(2):hi(2)) :: dYdy
    
    i = lo(1)

    do n=1,2
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_2d (i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dudy,dvdy)
    call comp_trans_deriv_x2_2d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,drhody,dYdy)

    !$omp parallel do private(j,n,rho,u,v,T,Y,h,rhoE) &
    !$omp private(dpdn, dudn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_p, d_Y, hcal, cpWT, gam1, cs2)
    do j=lo(2),hi(2)
          
       rho  = q  (i,j,qrho)
       u    = q  (i,j,qu)
       v    = q  (i,j,qv)
       T    = q  (i,j,qtemp)
       Y    = q  (i,j,qy1:qy1+nspecies-1)
       h    = q  (i,j,qh1:qh1+nspecies-1)
       rhoE = con(i,j,iene)
       
       dudn = dxinv(1)*first_deriv_rb(q(i:i+3,j,qu))
       dpdn = dxinv(1)*first_deriv_rb(q(i:i+3,j,qpres))
       
       cs2 = aux(ics,j)**2
       
       ! Simple 1D LODI 
       L(1) = (u-aux(ics,j))*0.5d0*(dpdn-rho*aux(ics,j)*dudn)
       L(2) = -inlet_eta*Ru*rho*(T-qin(iTin,j)) & 
            / (Lxdomain*aux(ics,j)*aux(iWbar,j))
       L(3) = inlet_eta*aux(ics,j)/Lxdomain*(v-qin(ivin,j))
       L(4) = inlet_eta*rho*cs2*(1.d0-Ma2_xlo)/(2.d0*Lxdomain) &
            * (u-qin(iuin,j))
       L(5:) = inlet_eta*aux(ics,j)/Lxdomain*(Y-qin(iYin1:,j))
          
       ! multi-D effects
       Ltr(2) = -v*(drhody(j) - dpdy(j)/cs2) 
       Ltr(3) = -(v*dvdy(j) + dpdy(j)/rho)
       Ltr(4) = -0.5*(v*dpdy(j)     &
               + rho*cs2*dvdy(j)     &
               + rho*aux(ics,j)*v*dudy(j))
       Ltr(5:)= -v*dYdy(:,j)

       L(2:) = L(2:) + Ltr(2:)

       ! viscous and reaction effects
       d_u = fd(i,j,imx) / rho
       d_v = fd(i,j,imy) / rho
          
       S_p = 0.d0
       d_p = fd(i,j,iene) - (d_u*con(i,j,imx)+d_v*con(i,j,imy))
       cpWT = aux(icp,j)*aux(iWbar,j)*T
       gam1 = aux(igamma,j) - 1.d0
       do n=1,nspecies
          hcal = h(n) - cpWT*inv_mwt(n)
          S_p    = S_p - hcal*aux(iwdot1+n-1,j)
          S_Y(n) = aux(iwdot1+n-1,j) / rho
          d_p    = d_p - hcal*fd(i,j,iry1+n-1)
          d_Y(n) = fd(i,j,iry1+n-1) / rho
       end do
       S_p = gam1 * S_p
       d_p = gam1 * d_p 
       
       L(2)  = L(2)  - (d_p + S_p) / cs2
       L(3)  = L(3)  + d_v
       L(4)  = L(4)  + 0.5d0*(S_p + d_p + rho*aux(ics,j)*d_u)
       L(5:) = L(5:) + S_Y + d_Y

       call LtoLHS_2d(1, L, lhs, aux(:,j), rho, u, v, T, Y, h, rhoE)
          
       rhs(i,j,:) = rhs(i,j,:) - lhs
       
    end do
    !$omp end parallel do

  end subroutine inlet_xlo_2d


  subroutine outlet_xhi_2d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(2), hi(2), ngq, ngc, dlo(2), dhi(2)
    double precision,intent(in   )::dx(2)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,-ngc+lo(2):hi(2)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),lo(2):hi(2),ncons)
    double precision,intent(in   )::aux(naux,lo(2):hi(2))

    integer :: i,j,n
    double precision :: dxinv(2)
    double precision :: rho, u, v, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, dvdn, drhodn, dYdn(nspecies)
    double precision :: L(4+nspecies), Ltr(4+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_v, d_p
    double precision :: hcal, cpWT, gam1

    double precision, dimension(lo(2):hi(2)) :: dpdy, dudy, dvdy
    
    i = hi(1)

    do n=1,2
       dxinv(n) = 1.0d0 / dx(n)
    end do

    call comp_trans_deriv_x_2d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dudy,dvdy)

    !$omp parallel do private(j,n,rho,u,v,T,pres,Y,h,rhoE) &
    !$omp private(dpdn, dudn, dvdn, drhodn, dYdn, L, Ltr, lhs) &
    !$omp private(S_p, S_Y, d_u, d_v, d_p, hcal, cpWT, gam1)
    do j=lo(2),hi(2)
          
       rho  = q  (i,j,qrho)
       u    = q  (i,j,qu)
       v    = q  (i,j,qv)
       pres = q  (i,j,qpres)
       T    = q  (i,j,qtemp)
       Y    = q  (i,j,qy1:qy1+nspecies-1)
       h    = q  (i,j,qh1:qh1+nspecies-1)
       rhoE = con(i,j,iene)
       
       drhodn     = dxinv(1)*first_deriv_lb(q(i-3:i,j,qrho))
       dudn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,qu))
       dvdn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,qv))
       dpdn       = dxinv(1)*first_deriv_lb(q(i-3:i,j,qpres))
       do n=1,nspecies
          dYdn(n) = dxinv(1)*first_deriv_lb(q(i-3:i,j,qy1+n-1))
       end do
       
       ! Simple 1D LODI 
       L(1) = sigma*aux(ics,j)*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*(pres-Pinfty)
       L(2) = u*(drhodn-dpdn/aux(ics,j)**2)
       L(3) = u*dvdn
       L(4) = (u+aux(ics,j))*0.5d0*(dpdn+rho*aux(ics,j)*dudn)
       L(5:) = u*dYdn
          
       ! multi-D effects
       Ltr(1) = -0.5d0*(v*dpdy(j) &
               + aux(igamma,j)*pres*dvdy(j) &
               - rho*aux(ics,j)*v*dudy(j))
       L(1) = L(1) + min(0.99d0, (1.0d0-abs(u)/aux(ics,j))) * Ltr(1)
          
       ! viscous and reaction effects
       d_u = fd(i,j,imx) / rho
       d_v = fd(i,j,imy) / rho

       S_p = 0.d0
       d_p = fd(i,j,iene) - (d_u*con(i,j,imx)+d_v*con(i,j,imy))
       cpWT = aux(icp,j)*aux(iWbar,j)*T
       gam1 = aux(igamma,j) - 1.d0
       do n=1,nspecies
          hcal = h(n) - cpWT*inv_mwt(n)
          S_p    = S_p - hcal*aux(iwdot1+n-1,j)
          S_Y(n) = aux(iwdot1+n-1,j) / rho
          d_p    = d_p - hcal*fd(i,j,iry1+n-1)
       end do
       S_p = gam1 * S_p
       d_p = gam1 * d_p 

       L(1) = L(1) + 0.5d0*(S_p + d_p - rho*aux(ics,j)*d_u)
          
       if (u < 0.d0) then
          L(2) = -S_p/aux(ics,j)**2
          L(3) = 0.d0
          L(5:) = S_Y      
             
          L(1) = 0.5d0*(S_p + d_p - rho*aux(ics,j)*d_u) + Ltr(1) &
               - outlet_eta*aux(igamma,j)*pres*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*u
       end if
          
       call LtoLHS_2d(1, L, lhs, aux(:,j), rho, u, v, T, Y, h, rhoE)
       
       rhs(i,j,:) = rhs(i,j,:) - lhs
       
    end do
    !$omp end parallel do
    
  end subroutine outlet_xhi_2d


  subroutine comp_trans_deriv_x_2d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dpdy,dudy,dvdy)
    integer, intent(in) :: i, lo(2), hi(2), ngq,dlo(2),dhi(2)
    double precision, intent(in) :: dxinv(2)
    double precision, intent(in) :: Q(-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,nprim)
    double precision, intent(out):: dpdy(lo(2):hi(2))
    double precision, intent(out):: dudy(lo(2):hi(2))
    double precision, intent(out):: dvdy(lo(2):hi(2))

    integer :: j, slo(2), shi(2)

    slo = dlo + stencil_ng
    shi = dhi - stencil_ng

    ! d()/dy
    !$omp parallel do private(j)
    do j=slo(2),shi(2)
       dudy(j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qu))
       dvdy(j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qv))
       dpdy(j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qpres))
    end do
    !$omp end parallel do

    ! lo-y boundary
    if (dlo(2) .eq. lo(2)) then
       j = lo(2)
       ! use completely right-biased stencil
       dudy(j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qu))
       dvdy(j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qv))
       dpdy(j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qpres))          
       
       j = lo(2)+1
       ! use 3rd-order slightly right-biased stencil
       dudy(j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qu))
       dvdy(j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qv))
       dpdy(j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qpres))          
       
       j = lo(2)+2
       ! use 4th-order stencil
       dudy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qu))
       dvdy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qv))
       dpdy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qpres))          
       
       j = lo(2)+3
       ! use 6th-order stencil
       dudy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qu))
       dvdy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qv))
       dpdy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qpres))          
    end if
    
    ! hi-y boundary
    if (dhi(2) .eq. hi(2)) then
       j = hi(2)-3
       ! use 6th-order stencil
       dudy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qu))
       dvdy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qv))
       dpdy(j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qpres))          
       
       j = hi(2)-2
       ! use 4th-order stencil
       dudy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qu))
       dvdy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qv))
       dpdy(j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qpres))          
       
       j = hi(2)-1
       ! use 3rd-order slightly left-biased stencil
       dudy(j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qu))
       dvdy(j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qv))
       dpdy(j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qpres))          
       
       j = hi(2)
       ! use completely left-biased stencil
       dudy(j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qu))
       dvdy(j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qv))
       dpdy(j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qpres))  
    end if

  end subroutine comp_trans_deriv_x_2d


  subroutine comp_trans_deriv_x2_2d(i,lo,hi,ngq,Q,dxinv,dlo,dhi,dddy,dYdy)
    integer, intent(in) :: i, lo(2), hi(2), ngq,dlo(2),dhi(2)
    double precision, intent(in) :: dxinv(2)
    double precision, intent(in) :: Q(-ngq+lo(1):hi(1)+ngq,-ngq+lo(2):hi(2)+ngq,nprim)
    double precision, intent(out):: dddy(         lo(2):hi(2))
    double precision, intent(out):: dYdy(nspecies,lo(2):hi(2))

    integer :: j, n, slo(2), shi(2)

    slo = dlo + stencil_ng
    shi = dhi - stencil_ng

    ! d()/dy
    !$omp parallel do private(j,n)
    do j=slo(2),shi(2)
       dddy     (j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_8(q(i,j-4:j+4,qy1+n-1))
       end do
    end do
    !$omp end parallel do

    ! lo-y boundary
    if (dlo(2) .eq. lo(2)) then
       j = lo(2)
       ! use completely right-biased stencil
       dddy     (j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_rb(q(i,j:j+3,qy1+n-1))          
       end do

       j = lo(2)+1
       ! use 3rd-order slightly right-biased stencil
       dddy     (j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_r3(q(i,j-1:j+2,qy1+n-1))          
       end do
       
       j = lo(2)+2
       ! use 4th-order stencil
       dddy     (j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qy1+n-1))          
       end do

       j = lo(2)+3
       ! use 6th-order stencil
       dddy     (j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qy1+n-1))          
       end do
    end if
    
    ! hi-y boundary
    if (dhi(2) .eq. hi(2)) then
       j = hi(2)-3
       ! use 6th-order stencil
       dddy     (j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_6(q(i,j-3:j+3,qy1+n-1))          
       end do
       
       j = hi(2)-2
       ! use 4th-order stencil
       dddy     (j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_4(q(i,j-2:j+2,qy1+n-1))          
       end do
       
       j = hi(2)-1
       ! use 3rd-order slightly left-biased stencil
       dddy     (j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_l3(q(i,j-2:j+1,qy1+n-1)) 
       end do
       
       j = hi(2)
       ! use completely left-biased stencil
       dddy     (j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qrho))
       do n=1,nspecies
          dYdy(n,j) = dxinv(2)*first_deriv_lb(q(i,j-3:j,qy1+n-1))  
       end do
    end if

  end subroutine comp_trans_deriv_x2_2d


! ----------------- 1D routine --------------------------

  subroutine outlet_xlo_1d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(1), hi(1), ngq, ngc, dlo(1), dhi(1)
    double precision,intent(in   )::dx(1)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),ncons)
    double precision,intent(in   )::aux(naux)

    integer :: i,n
    double precision :: dxinv(1)
    double precision :: rho, u, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, drhodn, dYdn(nspecies)
    double precision :: L(3+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_p
    double precision :: hcal, cpWT, gam1

    i = lo(1)

    dxinv(1) = 1.0d0 / dx(1)
          
    rho  = q  (i,qrho)
    u    = q  (i,qu)
    pres = q  (i,qpres)
    T    = q  (i,qtemp)
    Y    = q  (i,qy1:qy1+nspecies-1)
    h    = q  (i,qh1:qh1+nspecies-1)
    rhoE = con(i,iene)
          
    drhodn     = dxinv(1)*first_deriv_rb(q(i:i+3,qrho))
    dudn       = dxinv(1)*first_deriv_rb(q(i:i+3,qu))
    dpdn       = dxinv(1)*first_deriv_rb(q(i:i+3,qpres))
    do n=1,nspecies
       dYdn(n) = dxinv(1)*first_deriv_rb(q(i:i+3,qy1+n-1))
    end do
       
    ! Simple 1D LODI 
    L(1) = (u-aux(ics))*0.5d0*(dpdn-rho*aux(ics)*dudn)
    L(2) = u*(drhodn-dpdn/aux(ics)**2)
    L(3) = sigma*aux(ics)*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*(pres-Pinfty)
    L(4:) = u*dYdn
          
    ! viscous and reaction effects
    d_u = fd(i,imx) / rho
       
    S_p = 0.d0
    d_p = fd(i,iene) - d_u*con(i,imx)
    cpWT = aux(icp)*aux(iWbar)*T
    gam1 = aux(igamma) - 1.d0
    do n=1,nspecies
       hcal = h(n) - cpWT*inv_mwt(n)
       S_p    = S_p - hcal*aux(iwdot1+n-1)
       S_Y(n) = aux(iwdot1+n-1) / rho
       d_p    = d_p - hcal*fd(i,iry1+n-1)
    end do
    S_p = gam1 * S_p
    d_p = gam1 * d_p 
       
    L(3) = L(3) + 0.5d0*(S_p + d_p + rho*aux(ics)*d_u)
          
    if (u > 0.d0) then
       L(2) = -S_p/aux(ics)**2
       L(4:) = S_Y      
             
       L(3) = 0.5d0*(S_p + d_p + rho*aux(ics)*d_u) &
            + outlet_eta*aux(igamma)*pres*(1.d0-Ma2_xlo)/(2.d0*Lxdomain)*u
    end if
          
    call LtoLHS_1d(1, L, lhs, aux, rho, u, T, Y, h, rhoE)
          
    rhs(i,:) = rhs(i,:) - lhs
       
  end subroutine outlet_xlo_1d


  subroutine inlet_xlo_1d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,qin,dlo,dhi)
    integer, intent(in) :: lo(1), hi(1), ngq, ngc, dlo(1), dhi(1)
    double precision,intent(in   )::dx(1)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),ncons)
    double precision,intent(in   )::aux(naux)
    double precision,intent(in   )::qin(nqin)

    integer :: i,n
    double precision :: dxinv(1)
    double precision :: rho, u, v, T, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn
    double precision :: L(3+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_p, d_Y(nspecies)
    double precision :: hcal, cpWT, gam1, cs2

    i = lo(1)

    dxinv(1) = 1.0d0 / dx(1)

    rho  = q  (i,qrho)
    u    = q  (i,qu)
    T    = q  (i,qtemp)
    Y    = q  (i,qy1:qy1+nspecies-1)
    h    = q  (i,qh1:qh1+nspecies-1)
    rhoE = con(i,iene)
       
    dudn = dxinv(1)*first_deriv_rb(q(i:i+3,qu))
    dpdn = dxinv(1)*first_deriv_rb(q(i:i+3,qpres))
       
    cs2 = aux(ics)**2
       
    ! Simple 1D LODI 
    L(1) = (u-aux(ics))*0.5d0*(dpdn-rho*aux(ics)*dudn)
    L(2) = -inlet_eta*Ru*rho*(T-qin(iTin)) & 
         / (Lxdomain*aux(ics)*aux(iWbar))
    L(3) = inlet_eta*rho*cs2*(1.d0-Ma2_xlo)/(2.d0*Lxdomain) &
         * (u-qin(iuin))
    L(4:) = inlet_eta*aux(ics)/Lxdomain*(Y-qin(iYin1:))
          
    ! viscous and reaction effects
    d_u = fd(i,imx) / rho
          
    S_p = 0.d0
    d_p = fd(i,iene) - d_u*con(i,imx)
    cpWT = aux(icp)*aux(iWbar)*T
    gam1 = aux(igamma) - 1.d0
    do n=1,nspecies
       hcal = h(n) - cpWT*inv_mwt(n)
       S_p    = S_p - hcal*aux(iwdot1+n-1)
       S_Y(n) = aux(iwdot1+n-1) / rho
       d_p    = d_p - hcal*fd(i,iry1+n-1)
       d_Y(n) = fd(i,iry1+n-1) / rho
    end do
    S_p = gam1 * S_p
    d_p = gam1 * d_p 
       
    L(2)  = L(2)  - (d_p + S_p) / cs2
    L(3)  = L(3)  + 0.5d0*(S_p + d_p + rho*aux(ics)*d_u)
    L(4:) = L(4:) + S_Y + d_Y

    call LtoLHS_1d(1, L, lhs, aux, rho, u, T, Y, h, rhoE)
          
    rhs(i,:) = rhs(i,:) - lhs

  end subroutine inlet_xlo_1d


  subroutine outlet_xhi_1d(lo,hi,ngq,ngc,dx,Q,con,fd,rhs,aux,dlo,dhi)
    integer, intent(in) :: lo(1), hi(1), ngq, ngc, dlo(1), dhi(1)
    double precision,intent(in   )::dx(1)
    double precision,intent(in   )::Q  (-ngq+lo(1):hi(1)+ngq,nprim)
    double precision,intent(in   )::con(-ngc+lo(1):hi(1)+ngc,ncons)
    double precision,intent(in   )::fd (lo(1):hi(1),ncons)
    double precision,intent(inout)::rhs(lo(1):hi(1),ncons)
    double precision,intent(in   )::aux(naux)

    integer :: i,n
    double precision :: dxinv(1)
    double precision :: rho, u, T, pres, Y(nspecies), h(nspecies), rhoE
    double precision :: dpdn, dudn, drhodn, dYdn(nspecies)
    double precision :: L(3+nspecies), lhs(ncons)
    double precision :: S_p, S_Y(nspecies), d_u, d_p
    double precision :: hcal, cpWT, gam1

    i = hi(1)

    dxinv(1) = 1.0d0 / dx(1)
          
    rho  = q  (i,qrho)
    u    = q  (i,qu)
    pres = q  (i,qpres)
    T    = q  (i,qtemp)
    Y    = q  (i,qy1:qy1+nspecies-1)
    h    = q  (i,qh1:qh1+nspecies-1)
    rhoE = con(i,iene)
       
    drhodn     = dxinv(1)*first_deriv_lb(q(i-3:i,qrho))
    dudn       = dxinv(1)*first_deriv_lb(q(i-3:i,qu))
    dpdn       = dxinv(1)*first_deriv_lb(q(i-3:i,qpres))
    do n=1,nspecies
       dYdn(n) = dxinv(1)*first_deriv_lb(q(i-3:i,qy1+n-1))
    end do
    
    ! Simple 1D LODI 
    L(1) = sigma*aux(ics)*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*(pres-Pinfty)
    L(2) = u*(drhodn-dpdn/aux(ics)**2)
    L(3) = (u+aux(ics))*0.5d0*(dpdn+rho*aux(ics)*dudn)
    L(4:) = u*dYdn
          
    ! viscous and reaction effects
    d_u = fd(i,imx) / rho

    S_p = 0.d0
    d_p = fd(i,iene) - d_u*con(i,imx)
    cpWT = aux(icp)*aux(iWbar)*T
    gam1 = aux(igamma) - 1.d0
    do n=1,nspecies
       hcal = h(n) - cpWT*inv_mwt(n)
       S_p    = S_p - hcal*aux(iwdot1+n-1)
       S_Y(n) = aux(iwdot1+n-1) / rho
       d_p    = d_p - hcal*fd(i,iry1+n-1)
    end do
    S_p = gam1 * S_p
    d_p = gam1 * d_p 

    L(1) = L(1) + 0.5d0*(S_p + d_p - rho*aux(ics)*d_u)
          
    if (u < 0.d0) then
       L(2) = -S_p/aux(ics)**2
       L(4:) = S_Y      
             
       L(1) = 0.5d0*(S_p + d_p - rho*aux(ics)*d_u) & 
            - outlet_eta*aux(igamma)*pres*(1.d0-Ma2_xhi)/(2.d0*Lxdomain)*u
    end if
          
    call LtoLHS_1d(1, L, lhs, aux, rho, u, T, Y, h, rhoE)
       
    rhs(i,:) = rhs(i,:) - lhs
       
  end subroutine outlet_xhi_1d

