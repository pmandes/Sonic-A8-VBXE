; --- VBXE: offsety rejestrow w stronie (zp_fx) ---
VC_CORE_REV   = $40
VC_VIDEO      = $40
VC_XDL_ADR0   = $41
VC_XDL_ADR1   = $42
VC_XDL_ADR2   = $43
VC_CSEL       = $44
VC_PSEL       = $45
VC_CR         = $46
VC_CG         = $47
VC_CB         = $48
VC_BL_ADR0    = $50
VC_BL_ADR1    = $51
VC_BL_ADR2    = $52
VC_BLT_START  = $53
VC_IRQ        = $54
VC_MEMAC_B    = $5D
VC_MEMAC_CTL  = $5E
VC_MEMAC_BANK = $5F
; VIDEO_CONTROL: bit0 XDL; bit2 = 1 -> kolor 0 nakladki KRYJACY (Altirra 4.31; w dokumentacji FX
; bit "no_trans"). Przy bit2 = 0 piksele 0 sa przezroczyste i widac tlo GTIA (niebo GHZ = kolor 0!).
VIDEO_ON      = $05
