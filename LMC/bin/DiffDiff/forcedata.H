      REAL_T  forcing_xlength, forcing_ylength, forcing_zlength, forcing_epsilon
      REAL_T  forcing_time_scale_min, forcing_time_scale_max, force_scale, time_offset
      REAL_T  AXY(32), BXY(32), CXY(32), DXY(32), PXY(32), QXY(32), RXY(32)
      REAL_T  AZX(32), BZX(32), CZX(32), DZX(32), PZX(32), QZX(32), RZX(32)
      REAL_T  AYZ(32), BYZ(32), CYZ(32), DYZ(32), PYZ(32), QYZ(32), RYZ(32)
      REAL_T  FTX(0:32,0:32,0:32), FTY(0:32,0:32,0:32), FTZ(0:32,0:32,0:32), TAT(0:32,0:32,0:32), TAP(0:32,0:32,0:32)
      REAL_T  FPX(0:32,0:32,0:32), FPY(0:32,0:32,0:32), FPZ(0:32,0:32,0:32), FAX(0:32,0:32,0:32), FAY(0:32,0:32,0:32), FAZ(0:32,0:32,0:32)
      integer nmodes, nxmodes, nymodes, nzmodes, mode_start, blrandseed, hack_lz
      integer spectrum_type, forcing_type, use_rho_in_forcing, do_mode_division
      common /forcedtint/ blrandseed, nmodes, nxmodes, nymodes, nzmodes, mode_start, forcing_type, use_rho_in_forcing, do_mode_division, hack_lz
      common /forcedt/ force_scale, forcing_epsilon,
     &                 forcing_xlength, forcing_ylength, forcing_zlength,
     &                 forcing_time_scale_min, forcing_time_scale_max, time_offset,
     &                 AXY, BXY, CXY, DXY, PXY, QXY, RXY,
     &                 AZX, BZX, CZX, DZX, PZX, QZX, RZX,
     &                 AYZ, BYZ, CYZ, DYZ, PYZ, QYZ, RYZ,
     &                 FTX, FTY, FTZ, TAT, TAP,
     &                 FPX, FPY, FPZ, FAX, FAY, FAZ
