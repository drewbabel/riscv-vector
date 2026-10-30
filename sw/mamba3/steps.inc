STEP(norm) { OP(rmsnorm)(I_r, T_norm, u, DM); }

STEP(inproj) { OP(mv)(W_in, u, zx, NZX, DM); }

// Trapezoid coefficients
STEP(dta) {
    OP(add)(zx + O_DT, T_dtb, tmp, NH);
    softplusv(tmp, dt, NH);
    heavyneg(zx + O_A, A, NH, A_FLOOR);
    OP(mul)(A, dt, adt, NH);
    expv(adt, alpha, NH);
    sigmoidv(zx + O_TR, lam, NH);
    OP(mul)(lam, dt, gam, NH);
    OP(sub)(dt, gam, beta, NH);
    OP(mul)(beta, alpha, beta, NH);
}

STEP(bcnorm) {
    OP(rmsnorm)(zx + O_B, T_bnorm, bn, NS);
    OP(rmsnorm)(zx + O_C, T_cnorm, cn, NS);
    for (int h = 0; h < NH; ++h) {
        OP(add)(bn, T_bb + h * NS, kb + h * NS, NS);
        OP(add)(cn, T_cb + h * NS, qb + h * NS, NS);
    }
}

STEP(rotary) {
    tanhv(zx + O_ANG, th, NA);
    for (int h = 0; h < NH; ++h)
        phase(ang + h * NA, th, dt[h], NA);
    sincosv(ang, sn, cs, NH * NA);
    for (int h = 0; h < NH; ++h) {
        OP(rotary)(kb + h * NS, sn + h * NA, cs + h * NA, kr + h * NS, NA, NS);
        OP(rotary)(qb + h * NS, sn + h * NA, cs + h * NA, qr + h * NS, NA, NS);
    }
}

STEP(state) {
    for (int h = 0; h < NH; ++h) {
        OP(scale)(vp + h * P, beta[h], cb + h * P, P);
        OP(scale)(zx + O_X + h * P, gam[h], cg + h * P, P);
        OP(ssmupd)(H + h * P * NS, P, NS, alpha[h], cb + h * P, kp + h * NS,
                   cg + h * P, kr + h * NS);
    }
    // Carry k v forward
    memcpy(kp, kr, sizeof kp);
    memcpy(vp, zx + O_X, sizeof vp);
}

STEP(readout) {
    for (int h = 0; h < NH; ++h) {
        OP(ssmread)(H + h * P * NS, P, NS, qr + h * NS, yp + h * P);
        OP(scale)(zx + O_X + h * P, T_d[h], tmp + h * P, P);
    }
    OP(add)(yp, tmp, yp, DI);
}

STEP(gate) { OP(silugate)(yp, zx + O_Z, y, DI); }

STEP(outproj) {
    OP(mv)(W_out, y, out, DM, DI);
    OP(add)(I_r, out, r1, DM);
}

STEP(norm2) { OP(rmsnorm)(r1, T_norm2, u2, DM); }

STEP(fc1) { OP(mv)(W_f1, u2, f, 2 * DF, DM); }

STEP(glu) { OP(silugate)(f, f + DF, g, DF); }

STEP(fc2) {
    OP(mv)(W_f2, g, m, DM, DF);
    OP(add)(r1, m, ro, DM);
}
