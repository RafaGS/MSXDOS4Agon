; ==========================================================
; MSXDOS4Agon - MSX-DOS High Level Emulator for Agon MOS
;
; z80_cpu: Z80 CPU Emulation Engine 
;  
; Copyright (C) 2026 Rafa Gomez Sanchez (RafaG)
;
; This program is free software; you can redistribute it and/or modify
; it under the terms of the GNU General Public License as published by
; the Free Software Foundation; either version 2 of the License, or
; (at your option) any later version.
;
; This program is distributed in the hope that it will be useful,
; but WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
; GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public License
; along with this program; if not, write to the Free Software
; Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
; ==========================================================

CPU_IndexSel:    DB 0          ; 0 = IX ($DD), 1 = IY ($FD)
CPU_IO_TestPort: DB 0

; ----------------------------------------------------------
; E/S Básica (Stub)
; ----------------------------------------------------------
Z80_IO_ReadByte:
    LD A, (CPU_IO_TestPort)
    RET

Z80_IO_WriteByte:
    LD (CPU_IO_TestPort), A
    RET

; ----------------------------------------------------------
; Helpers de Banderas para E/S y Registros I/R
; ----------------------------------------------------------
Z80_IO_UpdateFlags:
    LD A, (CPU_AF)
    AND 1
    LD B, A
    LD A, E
    AND %10000000
    OR B
    LD B, A
    LD A, E
    OR A
    JR NZ, .in_nz
    SET 6, B
.in_nz:
    LD A, E
    AND %00101000
    OR B
    LD B, A
    LD A, E
    OR A
    JP PO, .in_po
    SET 2, B
.in_po:
    LD A, B
    LD (CPU_AF), A
    RET

Z80_LD_A_IR_Flags:
    LD (CPU_AF+1), A
    LD E, A
    LD A, (CPU_AF)
    AND 1
    LD B, A
    LD A, E
    AND %10000000
    OR B
    LD B, A
    LD A, E
    OR A
    JR NZ, .ldair_nz
    SET 6, B
.ldair_nz:
    LD A, E
    AND %00101000
    OR B
    LD B, A
    LD A, (CPU_IFF2)
    OR A
    JR Z, .ldair_no_pv
    SET 2, B
.ldair_no_pv:
    LD A, B
    LD (CPU_AF), A
    RET

; ----------------------------------------------------------
; Helpers de Control y Acceso a 16 Bits
; ----------------------------------------------------------
Z80_TruncateHL:
    PUSH BC
    LD BC, 0
    LD C, L
    LD B, H
    PUSH BC
    POP HL
    POP BC
    RET

Z80_GetPC:
    LD A, (CPU_PC)
    LD L, A
    LD A, (CPU_PC+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetPC:
    LD A, L
    LD (CPU_PC), A
    LD A, H
    LD (CPU_PC+1), A
    RET

Z80_IncPC:
    CALL Z80_GetPC
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    RET

Z80_AddRelPC:
    LD E, A
    RLCA
    SBC A, A
    LD D, A
    CALL Z80_GetPC
    ADD HL, DE
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    RET

Z80_GetBC:
    LD A, (CPU_BC)
    LD L, A
    LD A, (CPU_BC+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetBC:
    LD A, L
    LD (CPU_BC), A
    LD A, H
    LD (CPU_BC+1), A
    RET

Z80_GetDE:
    LD A, (CPU_DE)
    LD L, A
    LD A, (CPU_DE+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetDE:
    LD A, L
    LD (CPU_DE), A
    LD A, H
    LD (CPU_DE+1), A
    RET

Z80_GetHL:
    LD A, (CPU_HL)
    LD L, A
    LD A, (CPU_HL+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetHL:
    LD A, L
    LD (CPU_HL), A
    LD A, H
    LD (CPU_HL+1), A
    RET

Z80_GetSP:
    LD A, (CPU_SP)
    LD L, A
    LD A, (CPU_SP+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetSP:
    LD A, L
    LD (CPU_SP), A
    LD A, H
    LD (CPU_SP+1), A
    RET

Z80_GetIX:
    LD A, (CPU_IX)
    LD L, A
    LD A, (CPU_IX+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetIX:
    LD A, L
    LD (CPU_IX), A
    LD A, H
    LD (CPU_IX+1), A
    RET

Z80_GetIY:
    LD A, (CPU_IY)
    LD L, A
    LD A, (CPU_IY+1)
    LD H, A
    JP Z80_TruncateHL

Z80_SetIY:
    LD A, L
    LD (CPU_IY), A
    LD A, H
    LD (CPU_IY+1), A
    RET

Z80_GetIndexReg:
    PUSH AF
    LD A, (CPU_IndexSel)
    OR A
    JR NZ, .get_iy
    CALL Z80_GetIX
    POP AF
    RET
.get_iy:
    CALL Z80_GetIY
    POP AF
    RET

Z80_SetIndexReg:
    PUSH AF
    LD A, (CPU_IndexSel)
    OR A
    JR NZ, .set_iy
    CALL Z80_SetIX
    POP AF
    RET
.set_iy:
    CALL Z80_SetIY
    POP AF
    RET

Z80_GetIndexedAddress:
    PUSH AF
    PUSH DE
    
    ; 1. Extensión de signo del byte de desplazamiento 'd' (pasado en A)
    LD E, A
    RLCA
    SBC A, A
    LD D, A                     ; DE = Desplazamiento signado de 16-bit

    ; 2. Cargar IX o IY según CPU_IndexSel (0 = IX, 1 = IY)
    LD A, (CPU_IndexSel)
    OR A
    JR NZ, .use_iy

.use_ix:
    LD HL, (CPU_IX)
    JR .add_disp

.use_iy:
    LD HL, (CPU_IY)

.add_disp:
    ADD HL, DE                  ; HL = Base (IX/IY) + d
    CALL Z80_TruncateHL         ; Limpieza de bits 16-23 (ADL-safe)

    POP DE
    POP AF
    RET

Z80_AddTStates:
    PUSH DE
    LD DE, (CPU_TStates)
    ADD HL, DE
    LD (CPU_TStates), HL
    POP DE
    RET

Z80_GetImmByte:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    RET

Z80_StackPushWord:
    CALL Z80_GetSP
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetSP
    CALL MSXMemory_WriteWord
    RET

Z80_StackPopWord:
    CALL Z80_GetSP
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_GetSP
    INC HL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetSP
    POP HL
    RET

Z80_CheckCondition:
    AND %00000111
    OR A
    JR Z, .cond_nz
    DEC A
    JR Z, .cond_z
    DEC A
    JR Z, .cond_nc
    DEC A
    JR Z, .cond_c
    DEC A
    JR Z, .cond_po
    DEC A
    JR Z, .cond_pe
    DEC A
    JR Z, .cond_p
    LD A, (CPU_AF)
    AND %10000000
    JR NZ, .true
    JR .false
.cond_nz:
    LD A, (CPU_AF)
    AND %01000000
    JR Z, .true
    JR .false
.cond_z:
    LD A, (CPU_AF)
    AND %01000000
    JR NZ, .true
    JR .false
.cond_nc:
    LD A, (CPU_AF)
    AND %00000001
    JR Z, .true
    JR .false
.cond_c:
    LD A, (CPU_AF)
    AND %00000001
    JR NZ, .true
    JR .false
.cond_po:
    LD A, (CPU_AF)
    AND %00000100
    JR Z, .true
    JR .false
.cond_pe:
    LD A, (CPU_AF)
    AND %00000100
    JR NZ, .true
    JR .false
.cond_p:
    LD A, (CPU_AF)
    AND %10000000
    JR Z, .true
.false:
    XOR A
    RET
.true:
    LD A, 1
    RET

; ----------------------------------------------------------
; Helpers Universales de Registros Base de 8 Bits (Índice 0..7)
; ----------------------------------------------------------
Z80_GetReg8_Index:
    LD A, C
    AND %00000111
    OR A
    JR Z, .get_b
    DEC A
    JR Z, .get_c
    DEC A
    JR Z, .get_d
    DEC A
    JR Z, .get_e
    DEC A
    JR Z, .get_h
    DEC A
    JR Z, .get_l
    DEC A
    JR Z, .get_hl_ind
    LD A, (CPU_AF+1)
    LD E, A
    RET
.get_b:
    LD A, (CPU_BC+1)
    LD E, A
    RET
.get_c:
    LD A, (CPU_BC)
    LD E, A
    RET
.get_d:
    LD A, (CPU_DE+1)
    LD E, A
    RET
.get_e:
    LD A, (CPU_DE)
    LD E, A
    RET
.get_h:
    LD A, (CPU_HL+1)
    LD E, A
    RET
.get_l:
    LD A, (CPU_HL)
    LD E, A
    RET
.get_hl_ind:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    LD E, A
    RET

Z80_SetReg8_Index:
    AND %00000111
    OR A
    JR Z, .set_b
    DEC A
    JR Z, .set_c
    DEC A
    JR Z, .set_d
    DEC A
    JR Z, .set_e
    DEC A
    JR Z, .set_h
    DEC A
    JR Z, .set_l
    DEC A
    JR Z, .set_hl_ind
    LD A, E
    LD (CPU_AF+1), A
    RET
.set_b:
    LD A, E
    LD (CPU_BC+1), A
    RET
.set_c:
    LD A, E
    LD (CPU_BC), A
    RET
.set_d:
    LD A, E
    LD (CPU_DE+1), A
    RET
.set_e:
    LD A, E
    LD (CPU_DE), A
    RET
.set_h:
    LD A, E
    LD (CPU_HL+1), A
    RET
.set_l:
    LD A, E
    LD (CPU_HL), A
    RET
.set_hl_ind:
    CALL Z80_GetHL
    LD A, E
    CALL MSXMemory_WriteByte
    RET

; ----------------------------------------------------------
; Helpers ALU 8 Bits y Bloque (NATIVE eZ80 POWER - FIXED)
; ----------------------------------------------------------
Z80_ALU_INC_BYTE:
    LD A, (CPU_AF)
    RRA                 ; Sembrar el Carry nativo
    LD A, E
    INC A
    LD D, A             ; Guardar resultado en D
    PUSH AF
    POP BC              ; C = Banderas calculadas en silicio
    LD A, C
    LD (CPU_AF), A
    LD A, D             ; Devolver resultado en A
    RET

Z80_ALU_DEC_BYTE:
    LD A, (CPU_AF)
    RRA
    LD A, E
    DEC A
    LD D, A
    PUSH AF
    POP BC
    LD A, C             ; C = Banderas
    LD (CPU_AF), A
    LD A, D
    RET

Z80_ALU_ADD:
    LD A, (CPU_AF+1)
    ADD A, E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_ADC:
    LD A, (CPU_AF)
    RRA                 ; Inyectar nuestro Carry virtual
    LD A, (CPU_AF+1)
    ADC A, E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_SUB:
    LD A, (CPU_AF+1)
    SUB E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_SBC:
    LD A, (CPU_AF)
    RRA
    LD A, (CPU_AF+1)
    SBC A, E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_CP:
    LD A, (CPU_AF+1)
    CP E
    PUSH AF
    POP BC
    LD A, C             ; C = Banderas
    AND %11010111       ; Limpiar banderas X e Y
    LD B, A             ; Usar B como temporal
    LD A, E             ; En CP, X e Y vienen del operando
    AND %00101000
    OR B
    LD (CPU_AF), A
    RET

Z80_ALU_AND:
    LD A, (CPU_AF+1)
    AND E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_OR:
    LD A, (CPU_AF+1)
    OR E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET

Z80_ALU_XOR:
    LD A, (CPU_AF+1)
    XOR E
    LD (CPU_AF+1), A
    PUSH AF
    POP BC
    LD A, C
    LD (CPU_AF), A
    RET


; ----------------------------------------------------------
; Z80 16-bit ALU Core (Strict NMOS Z80 Software Calculation)
; ----------------------------------------------------------
Z80_Add16_Core:
    PUSH BC
    LD A, H
    LD B, A             ; B = H_orig
    LD A, D
    LD C, A             ; C = D_orig
    
    LD A, L
    ADD A, E
    LD E, A             ; E = L_res
    LD A, B
    ADC A, C
    LD D, A             ; D = H_res
    
    ; C flag
    LD A, 0
    JR NC, .add16_nc
    SET 0, A
.add16_nc:
    LD H, A             ; H = temp flag accumulator
    
    ; H flag (bit 11 carry) = (H_orig ^ D_orig ^ H_res) & 0x10
    LD A, B
    XOR C
    XOR D
    AND %00010000
    OR H
    LD H, A
    
    ; X, Y flags (from H_res)
    LD A, D
    AND %00101000
    OR H
    LD H, A
    
    ; Mix preserving S, Z, P/V. (N is forced to 0 by not setting bit 1)
    LD A, (CPU_AF)
    AND %11000100
    OR H
    LD (CPU_AF), A
    
    LD L, E
    LD H, D
    CALL Z80_TruncateHL
    POP BC
    
    PUSH HL
    LD HL, 11
    CALL Z80_AddTStates
    POP HL
    RET

Z80_AddHL_RR:
    CALL Z80_GetHL
    CALL Z80_Add16_Core
    JP Z80_SetHL

; ----------------------------------------------------------

Z80_ADC_HL_RR:
    CALL Z80_GetHL
    PUSH BC
    LD A, H
    LD B, A
    LD A, D
    LD C, A
    
    LD A, (CPU_AF)
    RRA                 ; Seed Carry
    
    LD A, L
    ADC A, E
    LD E, A
    LD A, B
    ADC A, C
    LD D, A
    
    ; C flag and N=0
    LD A, 0
    JR NC, .adc16_nc
    SET 0, A
.adc16_nc:
    LD H, A
    
    ; H flag
    LD A, B
    XOR C
    XOR D
    AND %00010000
    OR H
    LD H, A
    
    ; S flag
    LD A, D
    AND %10000000
    OR H
    LD H, A
    
    ; Z flag (16-bit)
    LD A, D
    OR E
    JR NZ, .adc16_nz
    LD A, H
    OR %01000000
    LD H, A
.adc16_nz:
    
    ; P/V flag (Overflow)
    LD A, B
    XOR C
    XOR $80
    LD C, A
    LD A, B
    XOR D
    AND C
    AND $80
    JR Z, .adc16_nv
    LD A, H
    OR %00000100
    LD H, A
.adc16_nv:
    
    ; X, Y flags
    LD A, D
    AND %00101000
    OR H
    LD (CPU_AF), A
    
    LD L, E
    LD H, D
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    POP BC
    
    PUSH HL
    LD HL, 15
    CALL Z80_AddTStates
    POP HL
    RET

; ----------------------------------------------------------

Z80_SBC_HL_RR:
    CALL Z80_GetHL
    PUSH BC
    LD A, H
    LD B, A
    LD A, D
    LD C, A
    
    LD A, (CPU_AF)
    RRA                 ; Seed Carry
    
    LD A, L
    SBC A, E
    LD E, A
    LD A, B
    SBC A, C
    LD D, A
    
    ; C flag and N=1 (bit 1)
    LD A, %00000010
    JR NC, .sbc16_nc
    SET 0, A
.sbc16_nc:
    LD H, A
    
    ; H flag (Borrow)
    LD A, B
    XOR C
    XOR D
    AND %00010000
    OR H
    LD H, A
    
    ; S flag
    LD A, D
    AND %10000000
    OR H
    LD H, A
    
    ; Z flag (16-bit)
    LD A, D
    OR E
    JR NZ, .sbc16_nz
    LD A, H
    OR %01000000
    LD H, A
.sbc16_nz:
    
    ; P/V flag (Overflow)
    LD A, B
    XOR C
    LD C, A
    LD A, B
    XOR D
    AND C
    AND $80
    JR Z, .sbc16_nv
    LD A, H
    OR %00000100
    LD H, A
.sbc16_nv:
    
    ; X, Y flags
    LD A, D
    AND %00101000
    OR H
    LD (CPU_AF), A
    
    LD L, E
    LD H, D
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    POP BC
    
    PUSH HL
    LD HL, 15
    CALL Z80_AddTStates
    POP HL
    RET


Z80_LDI_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_GetDE
    POP AF
    CALL MSXMemory_WriteByte
    CALL Z80_GetHL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    CALL Z80_GetDE
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetDE
    CALL Z80_GetBC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD A, (CPU_AF)
    AND %11000001
    LD B, A
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .ldi_bc_zero
    SET 2, B
.ldi_bc_zero:
    LD A, B
    LD (CPU_AF), A
    RET

Z80_LDD_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_GetDE
    POP AF
    CALL MSXMemory_WriteByte
    CALL Z80_GetHL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    CALL Z80_GetDE
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetDE
    CALL Z80_GetBC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD A, (CPU_AF)
    AND %11000001
    LD B, A
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .ldd_bc_zero
    SET 2, B
.ldd_bc_zero:
    LD A, B
    LD (CPU_AF), A
    RET

Z80_OUTI_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_GetBC
    POP AF
    CALL Z80_IO_WriteByte
    CALL Z80_GetHL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD A, (CPU_BC+1)
    DEC A
    LD (CPU_BC+1), A
    LD A, (CPU_AF)
    AND %00111101
    OR %00000010
    LD E, A
    LD A, (CPU_BC+1)
    OR A
    JR NZ, .outi_nz
    SET 6, E
.outi_nz:
    LD A, E
    LD (CPU_AF), A
    RET

Z80_OUTD_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_GetBC
    POP AF
    CALL Z80_IO_WriteByte
    CALL Z80_GetHL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD A, (CPU_BC+1)
    DEC A
    LD (CPU_BC+1), A
    LD A, (CPU_AF)
    AND %00111101
    OR %00000010
    LD E, A
    LD A, (CPU_BC+1)
    OR A
    JR NZ, .outd_nz
    SET 6, E
.outd_nz:
    LD A, E
    LD (CPU_AF), A
    RET

Z80_INI_Primitive:
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    PUSH AF
    CALL Z80_GetHL
    POP AF
    CALL MSXMemory_WriteByte
    CALL Z80_GetHL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD A, (CPU_BC+1)
    DEC A
    LD (CPU_BC+1), A
    LD A, (CPU_AF)
    AND %00111101
    OR %00000010
    LD E, A
    LD A, (CPU_BC+1)
    OR A
    JR NZ, .ini_nz
    SET 6, E
.ini_nz:
    LD A, E
    LD (CPU_AF), A
    RET

Z80_IND_Primitive:
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    PUSH AF
    CALL Z80_GetHL
    POP AF
    CALL MSXMemory_WriteByte
    CALL Z80_GetHL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD A, (CPU_BC+1)
    DEC A
    LD (CPU_BC+1), A
    LD A, (CPU_AF)
    AND %00111101
    OR %00000010
    LD E, A
    LD A, (CPU_BC+1)
    OR A
    JR NZ, .ind_nz
    SET 6, E
.ind_nz:
    LD A, E
    LD (CPU_AF), A
    RET

Z80_CPI_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    LD E, A
    LD A, (CPU_AF)
    AND 1
    LD B, A
    LD A, (CPU_AF+1)
    SUB E
    LD D, A
    SET 1, B
    LD A, D
    AND %10000000
    OR B
    LD B, A
    LD A, D
    OR A
    JR NZ, .cpi_nz
    SET 6, B
.cpi_nz:
    LD A, (CPU_AF+1)
    AND $0F
    LD C, A
    LD A, E
    AND $0F
    CP C
    JR Z, .cpi_nh
    JR C, .cpi_nh
    SET 4, B
.cpi_nh:
    CALL Z80_GetHL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    CALL Z80_GetBC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD A, L
    OR H
    JR Z, .cpi_bc_zero
    SET 2, B
.cpi_bc_zero:
    LD A, B
    LD (CPU_AF), A
    RET

Z80_CPD_Primitive:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    LD E, A
    LD A, (CPU_AF)
    AND 1
    LD B, A
    LD A, (CPU_AF+1)
    SUB E
    LD D, A
    SET 1, B
    LD A, D
    AND %10000000
    OR B
    LD B, A
    LD A, D
    OR A
    JR NZ, .cpd_nz
    SET 6, B
.cpd_nz:
    LD A, (CPU_AF+1)
    AND $0F
    LD C, A
    LD A, E
    AND $0F
    CP C
    JR Z, .cpd_nh
    JR C, .cpd_nh
    SET 4, B
.cpd_nh:
    CALL Z80_GetHL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    CALL Z80_GetBC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD A, L
    OR H
    JR Z, .cpd_bc_zero
    SET 2, B
.cpd_bc_zero:
    LD A, B
    LD (CPU_AF), A
    RET

; ----------------------------------------------------------
; Motor de Decodificación e Integración IX / IY ($DD y $FD)
; ----------------------------------------------------------
Z80_OP_DD_Dispatch:
    XOR A
    LD (CPU_IndexSel), A
    JP Z80_OP_Index_Common

Z80_OP_FD_Dispatch:
    LD A, 1
    LD (CPU_IndexSel), A
    JP Z80_OP_Index_Common

Z80_OP_Index_Common:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    LD C, A
    CALL Z80_IncPC

    LD A, C
    CP $CB
    JP Z, .idx_cb
    CP $21
    JP Z, .idx_ld_nn
    CP $22
    JP Z, .idx_ld_nn_ind
    CP $23
    JP Z, .idx_inc
    CP $2A
    JP Z, .idx_ld_ind_nn
    CP $2B
    JP Z, .idx_dec
    CP $09
    JP Z, .idx_add_bc
    CP $19
    JP Z, .idx_add_de
    CP $29
    JP Z, .idx_add_self
    CP $39
    JP Z, .idx_add_sp
    CP $E9
    JP Z, .idx_jp
    CP $E3
    JP Z, .idx_ex_sp
    CP $F9
    JP Z, .idx_ld_sp
    CP $34
    JP Z, .idx_inc_ind
    CP $35
    JP Z, .idx_dec_ind
    CP $36
    JP Z, .idx_ld_ind_n
    CP $E5
    JP Z, .idx_push
    CP $E1
    JP Z, .idx_pop

    LD A, C
    AND %11000000
    CP $40
    JP Z, .idx_block40
    LD A, C
    AND %11000000
    CP $80
    JP Z, .idx_block80

.fallback_idx:
    CALL Z80_GetPC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    RET

.idx_cb:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    LD C, A
    CALL Z80_IncPC
    POP AF

    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    PUSH HL

    CALL MSXMemory_ReadByte
    LD E, A

    LD A, C
    RLCA
    RLCA
    AND %00000011
    CP 1
    JR NZ, .idx_cb_not_bit

    POP HL
    LD A, H
    AND %00101000
    PUSH AF
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD B, A
    LD A, 1
    INC B
    DEC B
    JR Z, .idx_bit_shifted
.idx_bit_loop:
    RLCA
    DJNZ .idx_bit_loop
.idx_bit_shifted:
    AND E
    LD D, A

    LD A, (CPU_AF)
    AND 1
    LD B, A
    SET 4, B
    LD A, D
    OR A
    JR NZ, .idx_bit_nz
    SET 6, B
    SET 2, B
.idx_bit_nz:
    LD A, D
    AND %10000000        ; <-- NUEVO: Extraer el bit 7 (bandera S)
    OR B
    LD B, A              ; <-- Inyectarlo en las banderas

    POP AF
    OR B
    LD (CPU_AF), A
    LD HL, 20
    JP Z80_AddTStates

.idx_cb_not_bit:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD B, A

    LD A, C
    RLCA
    RLCA
    AND %00000011
    CP 3
    JR NZ, .idx_not_set

    LD A, 1
    INC B
    DEC B
    JR Z, .idx_set_done
.idx_set_loop:
    RLCA
    DJNZ .idx_set_loop
.idx_set_done:
    OR E
    LD E, A
    JP .idx_cb_writeback

.idx_not_set:
    CP 2
    JR NZ, .idx_not_res

    LD A, 1
    INC B
    DEC B
    JR Z, .idx_res_done
.idx_res_loop:
    RLCA
    DJNZ .idx_res_loop
.idx_res_done:
    CPL
    AND E
    LD E, A
    JP .idx_cb_writeback

.idx_not_res:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    OR A
    JR Z, .idx_rot_rlc
    DEC A
    JR Z, .idx_rot_rrc
    DEC A
    JR Z, .idx_rot_rl
    DEC A
    JR Z, .idx_rot_rr
    DEC A
    JR Z, .idx_rot_sla
    DEC A
    JR Z, .idx_rot_sra
    LD A, E
    AND 1
    LD B, A
    LD A, E
    SRL A
    LD E, A
    JR .idx_rot_flags

.idx_rot_sla:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, E
    SLA A
    LD E, A
    JR .idx_rot_flags

.idx_rot_sra:
    LD A, E
    AND 1
    LD B, A
    LD A, E
    SRA A
    LD E, A
    JR .idx_rot_flags

.idx_rot_rr:
    LD A, E
    AND 1
    LD B, A
    LD A, (CPU_AF)
    AND 1
    RRC A
    LD D, A
    LD A, E
    SRL A
    OR D
    LD E, A
    JR .idx_rot_flags

.idx_rot_rl:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, (CPU_AF)
    AND 1
    LD D, A
    LD A, E
    SLA A
    OR D
    LD E, A
    JR .idx_rot_flags

.idx_rot_rrc:
    LD A, E
    AND 1
    LD B, A
    LD A, E
    RRC A
    LD E, A
    JR .idx_rot_flags

.idx_rot_rlc:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, E
    RLCA
    LD E, A

.idx_rot_flags:
    LD D, 0
    LD A, E
    AND %10000000
    OR D
    LD D, A
    LD A, E
    OR A
    JR NZ, .idx_rot_nz
    SET 6, D
.idx_rot_nz:
    LD A, E
    AND %00101000
    OR D
    LD D, A
    LD A, E
    OR A
    JP PO, .idx_rot_po
    SET 2, D
.idx_rot_po:
    LD A, B
    AND 1
    OR D
    LD (CPU_AF), A

.idx_cb_writeback:
    POP HL
    LD A, E
    CALL MSXMemory_WriteByte
    LD HL, 23
    JP Z80_AddTStates

.idx_ld_nn:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetIndexReg
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD HL, 14
    JP Z80_AddTStates

.idx_ld_nn_ind:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP DE
    CALL Z80_GetIndexReg
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 20
    JP Z80_AddTStates

.idx_inc:
    CALL Z80_GetIndexReg
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetIndexReg
    LD HL, 10
    JP Z80_AddTStates

.idx_ld_ind_nn:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetIndexReg
    LD HL, 20
    JP Z80_AddTStates

.idx_dec:
    CALL Z80_GetIndexReg
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetIndexReg
    LD HL, 10
    JP Z80_AddTStates

.idx_add_bc:
    CALL Z80_GetBC
    EX DE, HL
    CALL Z80_GetIndexReg
    CALL Z80_Add16_Core
    CALL Z80_SetIndexReg
    LD HL, 4
    JP Z80_AddTStates

.idx_add_de:
    CALL Z80_GetDE
    EX DE, HL
    CALL Z80_GetIndexReg
    CALL Z80_Add16_Core
    CALL Z80_SetIndexReg
    LD HL, 4
    JP Z80_AddTStates

.idx_add_self:
    CALL Z80_GetIndexReg
    EX DE, HL
    CALL Z80_GetIndexReg
    CALL Z80_Add16_Core
    CALL Z80_SetIndexReg
    LD HL, 4
    JP Z80_AddTStates

.idx_add_sp:
    CALL Z80_GetSP
    EX DE, HL
    CALL Z80_GetIndexReg
    CALL Z80_Add16_Core
    CALL Z80_SetIndexReg
    LD HL, 4
    JP Z80_AddTStates

.idx_jp:
    CALL Z80_GetIndexReg
    CALL Z80_SetPC
    LD HL, 8
    JP Z80_AddTStates

.idx_ex_sp:
    CALL Z80_GetSP
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_GetIndexReg
    PUSH HL
    CALL Z80_GetSP
    POP DE
    CALL MSXMemory_WriteWord
    POP HL
    CALL Z80_SetIndexReg
    LD HL, 23
    JP Z80_AddTStates

.idx_ld_sp:
    CALL Z80_GetIndexReg
    CALL Z80_SetSP
    LD HL, 10
    JP Z80_AddTStates

.idx_push:
    ; PUSH IX / PUSH IY (DD E5 / FD E5)
    CALL Z80_GetIndexReg
    EX DE, HL
    CALL Z80_StackPushWord
    LD HL, 15
    JP Z80_AddTStates

.idx_pop:
    ; POP IX / POP IY (DD E1 / FD E1)
    CALL Z80_StackPopWord
    CALL Z80_SetIndexReg
    LD HL, 14
    JP Z80_AddTStates

.idx_inc_ind:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    PUSH HL
    CALL MSXMemory_ReadByte
    LD E, A
    CALL Z80_ALU_INC_BYTE
    POP HL
    CALL MSXMemory_WriteByte
    LD HL, 23
    JP Z80_AddTStates

.idx_dec_ind:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    PUSH HL
    CALL MSXMemory_ReadByte
    LD E, A
    CALL Z80_ALU_DEC_BYTE
    POP HL
    CALL MSXMemory_WriteByte
    LD HL, 23
    JP Z80_AddTStates

.idx_ld_ind_n:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    LD E, A
    CALL Z80_IncPC
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    LD A, E
    CALL MSXMemory_WriteByte
    LD HL, 19
    JP Z80_AddTStates

.idx_block40:
    LD A, C
    CP $76
    JP Z, .fallback_idx
    LD A, C
    AND %00000111
    CP 6
    JR Z, .idx_ld_r_ind
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    CP 6
    JR Z, .idx_ld_ind_r
    JP .fallback_idx

.idx_ld_r_ind:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    CALL MSXMemory_ReadByte
    LD E, A
    LD A, C
    RRCA
    RRCA
    RRCA
    CALL Z80_SetReg8_Index
    LD HL, 19
    JP Z80_AddTStates

.idx_ld_ind_r:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    LD A, C
    CALL Z80_GetReg8_Index
    LD D, E
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    LD A, D
    CALL MSXMemory_WriteByte
    LD HL, 19
    JP Z80_AddTStates

.idx_block80:
    LD A, C
    AND %00000111
    CP 6
    JP NZ, .fallback_idx

    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    CALL Z80_GetIndexReg
    CALL Z80_GetIndexedAddress
    CALL MSXMemory_ReadByte
    LD E, A

    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    OR A
    JR Z, .ialu_add
    DEC A
    JR Z, .ialu_adc
    DEC A
    JR Z, .ialu_sub
    DEC A
    JR Z, .ialu_sbc
    DEC A
    JR Z, .ialu_and
    DEC A
    JR Z, .ialu_xor
    DEC A
    JR Z, .ialu_or
.ialu_cp:
    CALL Z80_ALU_CP
    JR .ialu_done
.ialu_add:
    CALL Z80_ALU_ADD
    JR .ialu_done
.ialu_adc:
    CALL Z80_ALU_ADC
    JR .ialu_done
.ialu_sub:
    CALL Z80_ALU_SUB
    JR .ialu_done
.ialu_sbc:
    CALL Z80_ALU_SBC
    JR .ialu_done
.ialu_and:
    CALL Z80_ALU_AND
    JR .ialu_done
.ialu_xor:
    CALL Z80_ALU_XOR
    JR .ialu_done
.ialu_or:
    CALL Z80_ALU_OR
.ialu_done:
    LD HL, 19
    JP Z80_AddTStates

; ----------------------------------------------------------
; Motor de Ejecución de la Familia $ED
; ----------------------------------------------------------
Z80_OP_ED_Dispatch:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF

    CP $A1
    JR NZ, .not_cpi
    CALL Z80_CPI_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_cpi:

    CP $B1
    JR NZ, .not_cpir
    CALL Z80_CPI_Primitive
    LD A, (CPU_AF)
    AND %01000000
    JR NZ, .cpir_done
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .cpir_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.cpir_done:
    LD HL, 16
    JP Z80_AddTStates
.not_cpir:

    CP $A9
    JR NZ, .not_cpd
    CALL Z80_CPD_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_cpd:

    CP $B9
    JR NZ, .not_cpdr
    CALL Z80_CPD_Primitive
    LD A, (CPU_AF)
    AND %01000000
    JR NZ, .cpdr_done
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .cpdr_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.cpdr_done:
    LD HL, 16
    JP Z80_AddTStates
.not_cpdr:

    CP $A3
    JR NZ, .not_outi
    CALL Z80_OUTI_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_outi:

    CP $B3
    JR NZ, .not_otir
    CALL Z80_OUTI_Primitive
    LD A, (CPU_BC+1)
    OR A
    JR Z, .otir_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.otir_done:
    LD HL, 16
    JP Z80_AddTStates
.not_otir:

    CP $AB
    JR NZ, .not_outd
    CALL Z80_OUTD_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_outd:

    CP $BB
    JR NZ, .not_otdr
    CALL Z80_OUTD_Primitive
    LD A, (CPU_BC+1)
    OR A
    JR Z, .otdr_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.otdr_done:
    LD HL, 16
    JP Z80_AddTStates
.not_otdr:

    CP $A2
    JR NZ, .not_ini
    CALL Z80_INI_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_ini:

    CP $B2
    JR NZ, .not_inir
    CALL Z80_INI_Primitive
    LD A, (CPU_BC+1)
    OR A
    JR Z, .inir_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.inir_done:
    LD HL, 16
    JP Z80_AddTStates
.not_inir:

    CP $AA
    JR NZ, .not_ind
    CALL Z80_IND_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_ind:

    CP $BA
    JR NZ, .not_indr
    CALL Z80_IND_Primitive
    LD A, (CPU_BC+1)
    OR A
    JR Z, .indr_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.indr_done:
    LD HL, 16
    JP Z80_AddTStates
.not_indr:

    CP $A0
    JR NZ, .not_ldi
    CALL Z80_LDI_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_ldi:

    CP $B0
    JR NZ, .not_ldir
    CALL Z80_LDI_Primitive
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .ldir_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.ldir_done:
    LD HL, 16
    JP Z80_AddTStates
.not_ldir:

    CP $A8
    JR NZ, .not_ldd
    CALL Z80_LDD_Primitive
    LD HL, 16
    JP Z80_AddTStates
.not_ldd:

    CP $B8
    JR NZ, .not_lddr
    CALL Z80_LDD_Primitive
    CALL Z80_GetBC
    LD A, L
    OR H
    JR Z, .lddr_done
    CALL Z80_GetPC
    DEC HL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetPC
    LD HL, 21
    JP Z80_AddTStates
.lddr_done:
    LD HL, 16
    JP Z80_AddTStates
.not_lddr:

    CP $40
    JR NZ, .not_in_b_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_BC+1), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_b_c:

    CP $41
    JR NZ, .not_out_c_b
    CALL Z80_GetBC
    LD A, (CPU_BC+1)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_b:

    CP $48
    JR NZ, .not_in_c_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_BC), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_c_c:

    CP $49
    JR NZ, .not_out_c_c
    CALL Z80_GetBC
    LD A, (CPU_BC)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_c:

    CP $50
    JR NZ, .not_in_d_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_DE+1), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_d_c:

    CP $51
    JR NZ, .not_out_c_d
    CALL Z80_GetBC
    LD A, (CPU_DE+1)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_d:

    CP $58
    JR NZ, .not_in_e_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_DE), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_e_c:

    CP $59
    JR NZ, .not_out_c_e
    CALL Z80_GetBC
    LD A, (CPU_DE)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_e:

    CP $60
    JR NZ, .not_in_h_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_HL+1), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_h_c:

    CP $61
    JR NZ, .not_out_c_h
    CALL Z80_GetBC
    LD A, (CPU_HL+1)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_h:

    CP $68
    JR NZ, .not_in_l_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_HL), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_l_c:

    CP $69
    JR NZ, .not_out_c_l
    CALL Z80_GetBC
    LD A, (CPU_HL)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_l:

    CP $70
    JR NZ, .not_in_f_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_f_c:

    CP $71
    JR NZ, .not_out_c_zero
    CALL Z80_GetBC
    XOR A
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_zero:

    CP $78
    JR NZ, .not_in_a_c
    CALL Z80_GetBC
    CALL Z80_IO_ReadByte
    LD (CPU_AF+1), A
    LD E, A
    CALL Z80_IO_UpdateFlags
    LD HL, 12
    JP Z80_AddTStates
.not_in_a_c:

    CP $79
    JR NZ, .not_out_c_a
    CALL Z80_GetBC
    LD A, (CPU_AF+1)
    CALL Z80_IO_WriteByte
    LD HL, 12
    JP Z80_AddTStates
.not_out_c_a:

    CP $4A
    JR NZ, .not_adc_bc
    CALL Z80_GetBC
    EX DE, HL
    CALL Z80_ADC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_adc_bc:

    CP $5A
    JR NZ, .not_adc_de
    CALL Z80_GetDE
    EX DE, HL
    CALL Z80_ADC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_adc_de:

    CP $6A
    JR NZ, .not_adc_hl
    CALL Z80_GetHL
    EX DE, HL
    CALL Z80_ADC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_adc_hl:

    CP $7A
    JR NZ, .not_adc_sp
    CALL Z80_GetSP
    EX DE, HL
    CALL Z80_ADC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_adc_sp:

    CP $42
    JR NZ, .not_sbc_bc
    CALL Z80_GetBC
    EX DE, HL
    CALL Z80_SBC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_sbc_bc:

    CP $52
    JR NZ, .not_sbc_de
    CALL Z80_GetDE
    EX DE, HL
    CALL Z80_SBC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_sbc_de:

    CP $62
    JR NZ, .not_sbc_hl
    CALL Z80_GetHL
    EX DE, HL
    CALL Z80_SBC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_sbc_hl:

    CP $72
    JR NZ, .not_sbc_sp
    CALL Z80_GetSP
    EX DE, HL
    CALL Z80_SBC_HL_RR
    LD HL, 15
    JP Z80_AddTStates
.not_sbc_sp:

    CP $43
    JR NZ, .not_ld_nn_bc
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP DE
    CALL Z80_GetBC
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 20
    JP Z80_AddTStates
.not_ld_nn_bc:

    CP $53
    JR NZ, .not_ld_nn_de
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP DE
    CALL Z80_GetDE
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 20
    JP Z80_AddTStates
.not_ld_nn_de:

    CP $63
    JR NZ, .not_ld_nn_hl
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP DE
    CALL Z80_GetHL
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 20
    JP Z80_AddTStates
.not_ld_nn_hl:

    CP $73
    JR NZ, .not_ld_nn_sp
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP DE
    CALL Z80_GetSP
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 20
    JP Z80_AddTStates
.not_ld_nn_sp:

    CP $4B
    JR NZ, .not_ld_bc_nn
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetBC
    LD HL, 20
    JP Z80_AddTStates
.not_ld_bc_nn:

    CP $5B
    JR NZ, .not_ld_de_nn
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetDE
    LD HL, 20
    JP Z80_AddTStates
.not_ld_de_nn:

    CP $6B
    JR NZ, .not_ld_hl_nn
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetHL
    LD HL, 20
    JP Z80_AddTStates
.not_ld_hl_nn:

    CP $7B
    JR NZ, .not_ld_sp_nn
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetSP
    LD HL, 20
    JP Z80_AddTStates
.not_ld_sp_nn:

    CP $44
    JR NZ, .not_neg
    LD A, (CPU_AF+1)
    LD E, A
    XOR A
    LD (CPU_AF+1), A
    CALL Z80_ALU_SUB
    LD HL, 8
    JP Z80_AddTStates
.not_neg:

    CP $46
    JR NZ, .not_im0
    XOR A
    LD (CPU_IM), A
    LD HL, 8
    JP Z80_AddTStates
.not_im0:

    CP $56
    JR NZ, .not_im1
    LD A, 1
    LD (CPU_IM), A
    LD HL, 8
    JP Z80_AddTStates
.not_im1:

    CP $5E
    JR NZ, .not_im2
    LD A, 2
    LD (CPU_IM), A
    LD HL, 8
    JP Z80_AddTStates
.not_im2:

    CP $45
    JR Z, .exec_retn
    CP $4D
    JR NZ, .not_retn_reti
.exec_retn:
    LD A, (CPU_IFF2)
    LD (CPU_IFF1), A
    CALL Z80_StackPopWord
    CALL Z80_SetPC
    LD HL, 14
    JP Z80_AddTStates
.not_retn_reti:

    CP $47
    JR NZ, .not_ld_i_a
    LD A, (CPU_AF+1)
    LD (CPU_I), A
    LD HL, 9
    JP Z80_AddTStates
.not_ld_i_a:

    CP $4F
    JR NZ, .not_ld_r_a
    LD A, (CPU_AF+1)
    LD (CPU_R), A
    LD HL, 9
    JP Z80_AddTStates
.not_ld_r_a:

    CP $57
    JR NZ, .not_ld_a_i
    LD A, (CPU_I)
    CALL Z80_LD_A_IR_Flags
    LD HL, 9
    JP Z80_AddTStates
.not_ld_a_i:

    CP $5F
    JR NZ, .not_ld_a_r
    LD A, (CPU_R)
    CALL Z80_LD_A_IR_Flags
    LD HL, 9
    JP Z80_AddTStates
.not_ld_a_r:

    SCF
    RET

; ----------------------------------------------------------
; Motor de Sub-Operaciones (CB)
; ----------------------------------------------------------
Z80_CB_GetOperand:
    LD A, C
    AND %00000111
    OR A
    JR Z, .cb_get_b
    DEC A
    JR Z, .cb_get_c
    DEC A
    JR Z, .cb_get_d
    DEC A
    JR Z, .cb_get_e
    DEC A
    JR Z, .cb_get_h
    DEC A
    JR Z, .cb_get_l
    DEC A
    JR Z, .cb_get_hl
    LD A, (CPU_AF+1)
    LD E, A
    RET

.cb_get_b:
    LD A, (CPU_BC+1)
    LD E, A
    RET
.cb_get_c:
    LD A, (CPU_BC)
    LD E, A
    RET
.cb_get_d:
    LD A, (CPU_DE+1)
    LD E, A
    RET
.cb_get_e:
    LD A, (CPU_DE)
    LD E, A
    RET
.cb_get_h:
    LD A, (CPU_HL+1)
    LD E, A
    RET
.cb_get_l:
    LD A, (CPU_HL)
    LD E, A
    RET
.cb_get_hl:
    CALL Z80_GetHL
    CALL MSXMemory_ReadByte
    LD E, A
    RET

Z80_CB_SetOperand:
    PUSH AF
    LD A, C
    AND %00000111
    OR A
    JR Z, .cb_set_b
    DEC A
    JR Z, .cb_set_c
    DEC A
    JR Z, .cb_set_d
    DEC A
    JR Z, .cb_set_e
    DEC A
    JR Z, .cb_set_h
    DEC A
    JR Z, .cb_set_l
    DEC A
    JR Z, .cb_set_hl
    POP AF
    LD (CPU_AF+1), A
    RET

.cb_set_b:
    POP AF
    LD (CPU_BC+1), A
    RET
.cb_set_c:
    POP AF
    LD (CPU_BC), A
    RET
.cb_set_d:
    POP AF
    LD (CPU_DE+1), A
    RET
.cb_set_e:
    POP AF
    LD (CPU_DE), A
    RET
.cb_set_h:
    POP AF
    LD (CPU_HL+1), A
    RET
.cb_set_l:
    POP AF
    LD (CPU_HL), A
    RET
.cb_set_hl:
    POP AF
    PUSH AF
    CALL Z80_GetHL
    POP AF
    CALL MSXMemory_WriteByte
    RET

Z80_CB_UpdateRotateFlags:
    LD D, 0
    LD A, E
    AND %10000000
    OR D
    LD D, A

    LD A, E
    OR A
    JR NZ, .rot_nz
    SET 6, D
.rot_nz:

    LD A, E
    AND %00101000
    OR D
    LD D, A

    LD A, E
    OR A
    JP PO, .rot_po
    SET 2, D
.rot_po:

    LD A, B
    AND 1
    OR D
    LD (CPU_AF), A
    RET

Z80_OP_CB_Dispatch:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF

    LD C, A
    CALL Z80_CB_GetOperand

    LD A, C
    RLCA
    RLCA
    AND %00000011
    OR A
    JP Z, .cb_x0
    DEC A
    JP Z, .cb_x1
    DEC A
    JP Z, .cb_x2

.cb_x3:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD B, A
    LD A, 1
    INC B
    DEC B
    JR Z, .set_shifted
.set_shift_loop:
    RLCA
    DJNZ .set_shift_loop
.set_shifted:
    OR E
    CALL Z80_CB_SetOperand

    LD A, C
    AND %00000111
    CP 6
    JR Z, .cb_set_hl_time
    LD HL, 8
    JP Z80_AddTStates
.cb_set_hl_time:
    LD HL, 15
    JP Z80_AddTStates

.cb_x2:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD B, A
    LD A, 1
    INC B
    DEC B
    JR Z, .res_shifted
.res_shift_loop:
    RLCA
    DJNZ .res_shift_loop
.res_shifted:
    CPL
    AND E
    CALL Z80_CB_SetOperand

    LD A, C
    AND %00000111
    CP 6
    JR Z, .cb_res_hl_time
    LD HL, 8
    JP Z80_AddTStates
.cb_res_hl_time:
    LD HL, 15
    JP Z80_AddTStates

.cb_x1:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD B, A
    LD A, 1
    INC B
    DEC B
    JR Z, .bit_shifted
.bit_shift_loop:
    RLCA
    DJNZ .bit_shift_loop
.bit_shifted:
    AND E
    LD D, A

    LD A, (CPU_AF)
    AND 1
    LD B, A

    SET 4, B

    LD A, D
    OR A
    JR NZ, .bit_nz
    SET 6, B
    SET 2, B
.bit_nz:
    ; ---> NUEVO: Capturar y setear la bandera de Signo (S) si el bit probado era el 7
    LD A, D
    AND %10000000        ; Extraer el bit 7
    OR B
    LD B, A              ; Ahora B tiene S, Z, H, P/V, C

    LD A, C
    AND %00000111
    CP 6
    JR NZ, .bit_from_reg
    CALL Z80_GetHL
    LD A, H
    JR .bit_apply_yx
.bit_from_reg:
    LD A, E
.bit_apply_yx:
    AND %00101000
    OR B
    LD (CPU_AF), A

    LD A, C
    AND %00000111
    CP 6
    JR Z, .cb_bit_hl_time
    LD HL, 8
    JP Z80_AddTStates
.cb_bit_hl_time:
    LD HL, 12
    JP Z80_AddTStates

.cb_x0:
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    OR A
    JR Z, .rot_rlc
    DEC A
    JR Z, .rot_rrc
    DEC A
    JR Z, .rot_rl
    DEC A
    JR Z, .rot_rr
    DEC A
    JR Z, .rot_sla
    DEC A
    JR Z, .rot_sra
    DEC A
    JR Z, .rot_sll

.rot_srl:
    LD A, E
    AND 1
    LD B, A
    LD A, E
    SRL A
    LD E, A
    JR .rot_finish

.rot_sll:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, E
    SLA A
    SET 0, A             ; <-- ¡EL SECRETO DEL Z80! SLL inyecta un 1.
    LD E, A
    JR .rot_finish

.rot_sla:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, E
    SLA A
    LD E, A
    JR .rot_finish

.rot_sra:
    LD A, E
    AND 1
    LD B, A
    LD A, E
    SRA A
    LD E, A
    JR .rot_finish

.rot_rr:
    LD A, E
    AND 1
    LD B, A
    LD A, (CPU_AF)
    AND 1
    RRC A
    LD D, A
    LD A, E
    SRL A
    OR D
    LD E, A
    JR .rot_finish

.rot_rl:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, (CPU_AF)
    AND 1
    LD D, A
    LD A, E
    SLA A
    OR D
    LD E, A
    JR .rot_finish

.rot_rrc:
    LD A, E
    AND 1
    LD B, A
    LD A, E
    RRC A
    LD E, A
    JR .rot_finish

.rot_rlc:
    LD A, E
    RLCA
    AND 1
    LD B, A
    LD A, E
    RLCA
    LD E, A

.rot_finish:
    LD A, E
    CALL Z80_CB_SetOperand
    CALL Z80_CB_UpdateRotateFlags

    LD A, C
    AND %00000111
    CP 6
    JR Z, .cb_rot_hl_time
    LD HL, 8
    JP Z80_AddTStates
.cb_rot_hl_time:
    LD HL, 15
    JP Z80_AddTStates

; ----------------------------------------------------------
; Motor Base: Reset y Ejecución Principal
; ----------------------------------------------------------
Z80_Reset:
    XOR A
    LD (CPU_AF), A
    LD (CPU_AF+1), A
    LD (CPU_BC), A
    LD (CPU_BC+1), A
    LD (CPU_DE), A
    LD (CPU_DE+1), A
    LD (CPU_HL), A
    LD (CPU_HL+1), A
    LD (CPU_IX), A
    LD (CPU_IX+1), A
    LD (CPU_IY), A
    LD (CPU_IY+1), A

    LD (CPU_AF_ALT), A
    LD (CPU_AF_ALT+1), A
    LD (CPU_BC_ALT), A
    LD (CPU_BC_ALT+1), A
    LD (CPU_DE_ALT), A
    LD (CPU_DE_ALT+1), A
    LD (CPU_HL_ALT), A
    LD (CPU_HL_ALT+1), A

    LD (CPU_PC), A
    LD (CPU_PC+1), A
    LD (CPU_SP), A
    LD (CPU_SP+1), A

    LD (CPU_I), A
    LD (CPU_R), A
    LD (CPU_IFF1), A
    LD (CPU_IFF2), A
    LD (CPU_IM), A
    LD (CPU_HALT), A
    LD (CPU_IO_TestPort), A
    LD (CPU_IndexSel), A

    LD HL, 0
    LD (CPU_TStates), HL
    RET

; ----------------------------------------------------------
; Motor Base: Reset y Ejecución Principal
; ----------------------------------------------------------
Z80_Step:
    LD A, (CPU_HALT)
    OR A
    RET NZ

    ; --- MSX-DOS HLE HOOK (Interceptor) ---
    CALL Z80_GetPC
    LD A, H
    OR A
    JR NZ, .normal_step     ; Si H != 0x00, seguimos normal
    LD A, L
    CP $05
    JR NZ, .normal_step     ; Si L != 0x05, seguimos normal
    
    ; ¡Bingo! La CPU virtual ha llegado a 0x0005.
    ; Cedemos el control al anfitrión para que procese el BDOS.
    CALL MSX_BDOS_Hook
    RET                     ; Salimos de Z80_Step esta iteración

.normal_step:
    XOR A
    LD (CPU_IndexSel), A

    CALL Z80_GetPC

    CALL MSXMemory_ReadByte
    PUSH AF

    CALL Z80_IncPC

    POP AF
    LD L, A
    LD H, 0
    LD BC, 0
    LD C, L
    LD B, H
    PUSH BC
    POP HL
    ADD HL, HL
    ADD HL, BC

    LD BC, Z80_DispatchTable
    ADD HL, BC

    LD HL, (HL)
    JP (HL)

; ----------------------------------------------------------
; Handlers $00-$3F y Opcodes Sueltos Base
; ----------------------------------------------------------
Z80_OP_00:
    LD HL, 4
    CALL Z80_AddTStates
    OR A
    RET

Z80_OP_Block00_INC_R:
    PUSH AF                 ; Preservar opcode original
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD C, A                 ; C = índice de registro origen
    CALL Z80_GetReg8_Index
    CALL Z80_ALU_INC_BYTE   ; A = nuevo valor (destruye D internamente)
    LD E, A                 ; E = valor a guardar
    POP AF                  ; Recuperar opcode original
    PUSH AF                 ; Guardar de nuevo para el cálculo de T-states
    RRCA
    RRCA
    RRCA
    CALL Z80_SetReg8_Index  ; Guardar E en el índice destino calculado a partir de A
    POP AF                  ; Recuperar opcode original
    RRCA
    RRCA
    RRCA
    AND %00000111
    CP 6
    JR Z, .inc_hl_time
    LD HL, 4
    JP Z80_AddTStates
.inc_hl_time:
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_Block00_DEC_R:
    PUSH AF                 ; Preservar opcode original
    RRCA
    RRCA
    RRCA
    AND %00000111
    LD C, A                 ; C = índice de registro origen
    CALL Z80_GetReg8_Index
    CALL Z80_ALU_DEC_BYTE   ; (destruye D internamente)
    LD E, A
    POP AF
    PUSH AF
    RRCA
    RRCA
    RRCA
    CALL Z80_SetReg8_Index
    POP AF
    RRCA
    RRCA
    RRCA
    AND %00000111
    CP 6
    JR Z, .dec_hl_time
    LD HL, 4
    JP Z80_AddTStates
.dec_hl_time:
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_Block00_LD_R_N:
    PUSH AF
    CALL Z80_GetImmByte
    LD E, A
    POP AF
    PUSH AF
    LD C, A
    RRCA
    RRCA
    RRCA
    CALL Z80_SetReg8_Index
    POP AF

    LD C, A
    RRCA
    RRCA
    RRCA
    AND %00000111
    CP 6
    JR Z, .ld_rn_hl_time
    LD HL, 7
    JP Z80_AddTStates
.ld_rn_hl_time:
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_01:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetBC
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_02:
    CALL Z80_GetBC
    LD A, (CPU_AF+1)
    CALL MSXMemory_WriteByte
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_03:
    CALL Z80_GetBC
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_07:
    LD A, (CPU_AF+1)
    RLCA
    LD (CPU_AF+1), A
    LD E, A
    LD A, (CPU_AF)
    AND %11000100
    LD B, A
    LD A, E
    AND %00101000
    OR B
    LD B, A
    LD A, E
    AND 1
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_08:
    LD A, (CPU_AF)
    LD B, A
    LD A, (CPU_AF_ALT)
    LD (CPU_AF), A
    LD A, B
    LD (CPU_AF_ALT), A

    LD A, (CPU_AF+1)
    LD B, A
    LD A, (CPU_AF_ALT+1)
    LD (CPU_AF+1), A
    LD A, B
    LD (CPU_AF_ALT+1), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_09:
    CALL Z80_GetBC
    EX DE, HL
    JP Z80_AddHL_RR

Z80_OP_0A:
    CALL Z80_GetBC
    CALL MSXMemory_ReadByte
    LD (CPU_AF+1), A
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_0B:
    CALL Z80_GetBC
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetBC
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_0F:
    LD A, (CPU_AF+1)
    RRCA
    LD (CPU_AF+1), A
    LD E, A
    LD A, (CPU_AF)
    AND %11000100
    LD B, A
    LD A, E
    AND %00101000
    OR B
    LD B, A
    LD A, E
    AND %10000000
    RRCA
    RRCA
    RRCA
    RRCA
    RRCA
    RRCA
    RRCA
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_10:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    LD A, (CPU_BC+1)
    DEC A
    LD (CPU_BC+1), A
    JR NZ, .djnz_taken
    POP AF
    LD HL, 8
    JP Z80_AddTStates
.djnz_taken:
    POP AF
    CALL Z80_AddRelPC
    LD HL, 13
    JP Z80_AddTStates

Z80_OP_11:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetDE
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_12:
    CALL Z80_GetDE
    LD A, (CPU_AF+1)
    CALL MSXMemory_WriteByte
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_13:
    CALL Z80_GetDE
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetDE
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_17:
    LD A, (CPU_AF)
    RRA                 ; TRUCO: Mete el bit 0 de CPU_AF en el Carry nativo del eZ80
    LD A, (CPU_AF+1)
    RLA                 ; Ahora RLA nativo usa el Carry correcto y lo actualiza
    LD (CPU_AF+1), A
    LD E, A             ; E = Nuevo Acumulador
    
    LD A, 0
    ADC A, 0            ; Extrae el nuevo Carry nativo a A (vale 0 o 1)
    LD D, A             ; D = Nuevo Carry
    
    LD A, (CPU_AF)
    AND %11000100       ; Preservar S, Z, P/V. (RLA pone H y N a 0)
    OR D                ; Inyectar el nuevo Carry
    LD B, A
    LD A, E
    AND %00101000       ; Extraer banderas indocumentadas X e Y del Acumulador
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_18:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    CALL Z80_AddRelPC
    LD HL, 12
    JP Z80_AddTStates

Z80_OP_19:
    CALL Z80_GetDE
    EX DE, HL
    JP Z80_AddHL_RR

Z80_OP_1A:
    CALL Z80_GetDE
    CALL MSXMemory_ReadByte
    LD (CPU_AF+1), A
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_1B:
    CALL Z80_GetDE
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetDE
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_1F:
    LD A, (CPU_AF)
    RRA                 ; TRUCO: Sembrar el Carry nativo del eZ80
    LD A, (CPU_AF+1)
    RRA                 ; RRA nativo con el Carry correcto
    LD (CPU_AF+1), A
    LD E, A             ; E = Nuevo Acumulador
    
    LD A, 0
    ADC A, 0            ; Extraer el nuevo Carry nativo
    LD D, A             ; D = Nuevo Carry
    
    LD A, (CPU_AF)
    AND %11000100       ; Preservar S, Z, P/V. (RRA pone H y N a 0)
    OR D                ; Inyectar el nuevo Carry
    LD B, A
    LD A, E
    AND %00101000       ; Extraer banderas indocumentadas X e Y del Acumulador
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_JR_Cond_Common:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF

    PUSH AF
    LD A, E
    CALL Z80_CheckCondition
    OR A
    JR NZ, .jr_taken

    POP AF
    LD HL, 7
    JP Z80_AddTStates

.jr_taken:
    POP AF
    CALL Z80_AddRelPC
    LD HL, 12
    JP Z80_AddTStates

Z80_OP_20:
    LD E, 0
    JP Z80_OP_JR_Cond_Common
Z80_OP_28:
    LD E, 1
    JP Z80_OP_JR_Cond_Common
Z80_OP_30:
    LD E, 2
    JP Z80_OP_JR_Cond_Common
Z80_OP_38:
    LD E, 3
    JP Z80_OP_JR_Cond_Common

Z80_OP_21:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetHL
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_22:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    CALL Z80_GetHL
    POP DE
    EX DE, HL
    CALL MSXMemory_WriteWord
    LD HL, 16
    JP Z80_AddTStates

Z80_OP_23:
    CALL Z80_GetHL
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_27:
    LD A, (CPU_AF+1)
    LD B, A             ; B = Acumulador
    LD A, (CPU_AF)
    LD C, A             ; C = Banderas (¡C es la parte baja!)
    
    PUSH BC
    POP AF              ; ¡A y F nativos cargados a la perfección!
    DAA                 ; DAA del hardware real
    PUSH AF
    POP BC              ; B = Nuevo Acumulador, C = Nuevas Banderas
    
    LD A, B
    LD (CPU_AF+1), A
    LD A, C
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_29:
    CALL Z80_GetHL
    EX DE, HL
    JP Z80_AddHL_RR

Z80_OP_2A:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadWord
    CALL Z80_SetHL
    LD HL, 16
    JP Z80_AddTStates

Z80_OP_2B:
    CALL Z80_GetHL
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetHL
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_2F:
    LD A, (CPU_AF+1)
    CPL
    LD (CPU_AF+1), A
    LD E, A

    LD A, (CPU_AF)
    AND %11000101
    OR %00010010
    LD B, A
    LD A, E
    AND %00101000
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_31:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetSP
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_32:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    LD A, (CPU_AF+1)
    CALL MSXMemory_WriteByte
    LD HL, 13
    JP Z80_AddTStates

Z80_OP_33:
    CALL Z80_GetSP
    INC HL
    CALL Z80_TruncateHL
    CALL Z80_SetSP
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_37:
    LD A, (CPU_AF)
    AND %11000100
    OR %00000001
    LD B, A
    LD A, (CPU_AF+1)
    AND %00101000
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_39:
    CALL Z80_GetSP
    EX DE, HL
    JP Z80_AddHL_RR

Z80_OP_3A:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    POP HL
    CALL MSXMemory_ReadByte
    LD (CPU_AF+1), A
    LD HL, 13
    JP Z80_AddTStates

Z80_OP_3B:
    CALL Z80_GetSP
    DEC HL
    CALL Z80_TruncateHL
    CALL Z80_SetSP
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_3E:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    LD (CPU_AF+1), A
    CALL Z80_IncPC

    LD HL, 7
    JP Z80_AddTStates

Z80_OP_3F:
    LD A, (CPU_AF)
    LD B, A
    AND 1
    LD C, A
    XOR 1
    LD E, A
    LD A, B
    AND %11000100
    OR E
    LD B, A
    LD A, C
    OR A
    JR Z, .ccf_no_h
    SET 4, B
.ccf_no_h:
    LD A, (CPU_AF+1)
    AND %00101000
    OR B
    LD (CPU_AF), A
    LD HL, 4
    JP Z80_AddTStates

; ----------------------------------------------------------
; Motor de Decodificación Compacta $40-$7F (LD r, r')
; ----------------------------------------------------------
Z80_OP_Block40:
    PUSH AF
    LD C, A
    CALL Z80_GetReg8_Index
    POP AF
    PUSH AF
    LD C, A
    RRCA
    RRCA
    RRCA
    CALL Z80_SetReg8_Index
    POP AF

    LD C, A
    AND %00000111
    CP 6
    JR Z, .ld_hl_time
    LD A, C
    RRCA
    RRCA
    RRCA
    AND %00000111
    CP 6
    JR Z, .ld_hl_time
    LD HL, 4
    JP Z80_AddTStates
.ld_hl_time:
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_76:
    LD A, 1
    LD (CPU_HALT), A
    LD HL, 4
    JP Z80_AddTStates

; ----------------------------------------------------------
; Motor de Decodificación Compacta $80-$BF (ALU A, r)
; ----------------------------------------------------------
Z80_OP_Block80:
    PUSH AF
    LD C, A
    CALL Z80_GetReg8_Index
    POP AF
    PUSH AF
    LD C, A
    RRCA
    RRCA
    RRCA
    AND %00000111
    OR A
    JR Z, .alu_add
    DEC A
    JR Z, .alu_adc
    DEC A
    JR Z, .alu_sub
    DEC A
    JR Z, .alu_sbc
    DEC A
    JR Z, .alu_and
    DEC A
    JR Z, .alu_xor
    DEC A
    JR Z, .alu_or
.alu_cp:
    CALL Z80_ALU_CP
    JR .alu_done
.alu_add:
    CALL Z80_ALU_ADD
    JR .alu_done
.alu_adc:
    CALL Z80_ALU_ADC
    JR .alu_done
.alu_sub:
    CALL Z80_ALU_SUB
    JR .alu_done
.alu_sbc:
    CALL Z80_ALU_SBC
    JR .alu_done
.alu_and:
    CALL Z80_ALU_AND
    JR .alu_done
.alu_xor:
    CALL Z80_ALU_XOR
    JR .alu_done
.alu_or:
    CALL Z80_ALU_OR
.alu_done:
    POP AF
    LD C, A
    AND %00000111
    CP 6
    JR Z, .alu_hl_time
    LD HL, 4
    JP Z80_AddTStates
.alu_hl_time:
    LD HL, 7
    JP Z80_AddTStates

; ----------------------------------------------------------
; Handlers de Control y Especiales $C0-$FF
; ----------------------------------------------------------
Z80_OP_JP_Cond_Common:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD A, E
    CALL Z80_CheckCondition
    OR A
    JR NZ, .jp_taken
    POP HL
    LD HL, 10
    JP Z80_AddTStates
.jp_taken:
    POP HL
    CALL Z80_SetPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_C2:
    LD E, 0
    JP Z80_OP_JP_Cond_Common
Z80_OP_CA:
    LD E, 1
    JP Z80_OP_JP_Cond_Common
Z80_OP_D2:
    LD E, 2
    JP Z80_OP_JP_Cond_Common
Z80_OP_DA:
    LD E, 3
    JP Z80_OP_JP_Cond_Common
Z80_OP_E2:
    LD E, 4
    JP Z80_OP_JP_Cond_Common
Z80_OP_EA:
    LD E, 5
    JP Z80_OP_JP_Cond_Common
Z80_OP_F2:
    LD E, 6
    JP Z80_OP_JP_Cond_Common
Z80_OP_FA:
    LD E, 7
    JP Z80_OP_JP_Cond_Common

Z80_OP_CALL_Cond_Common:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_IncPC
    CALL Z80_IncPC
    LD A, E
    CALL Z80_CheckCondition
    OR A
    JR NZ, .call_taken
    POP HL
    LD HL, 10
    JP Z80_AddTStates
.call_taken:
    CALL Z80_GetPC
    EX DE, HL
    CALL Z80_StackPushWord
    POP HL
    CALL Z80_SetPC
    LD HL, 17
    JP Z80_AddTStates

Z80_OP_C4:
    LD E, 0
    JP Z80_OP_CALL_Cond_Common
Z80_OP_CC:
    LD E, 1
    JP Z80_OP_CALL_Cond_Common
Z80_OP_D4:
    LD E, 2
    JP Z80_OP_CALL_Cond_Common
Z80_OP_DC:
    LD E, 3
    JP Z80_OP_CALL_Cond_Common
Z80_OP_E4:
    LD E, 4
    JP Z80_OP_CALL_Cond_Common
Z80_OP_EC:
    LD E, 5
    JP Z80_OP_CALL_Cond_Common
Z80_OP_F4:
    LD E, 6
    JP Z80_OP_CALL_Cond_Common
Z80_OP_FC:
    LD E, 7
    JP Z80_OP_CALL_Cond_Common

Z80_OP_RET_Cond_Common:
    LD A, E
    CALL Z80_CheckCondition
    OR A
    JR NZ, .ret_taken
    LD HL, 5
    JP Z80_AddTStates
.ret_taken:
    CALL Z80_StackPopWord
    CALL Z80_SetPC
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_C0:
    LD E, 0
    JP Z80_OP_RET_Cond_Common
Z80_OP_C8:
    LD E, 1
    JP Z80_OP_RET_Cond_Common
Z80_OP_D0:
    LD E, 2
    JP Z80_OP_RET_Cond_Common
Z80_OP_D8:
    LD E, 3
    JP Z80_OP_RET_Cond_Common
Z80_OP_E0:
    LD E, 4
    JP Z80_OP_RET_Cond_Common
Z80_OP_E8:
    LD E, 5
    JP Z80_OP_RET_Cond_Common
Z80_OP_F0:
    LD E, 6
    JP Z80_OP_RET_Cond_Common
Z80_OP_F8:
    LD E, 7
    JP Z80_OP_RET_Cond_Common

Z80_OP_C1:
    CALL Z80_StackPopWord
    CALL Z80_SetBC
    LD HL, 10
    JP Z80_AddTStates
Z80_OP_D1:
    CALL Z80_StackPopWord
    CALL Z80_SetDE
    LD HL, 10
    JP Z80_AddTStates
Z80_OP_E1:
    CALL Z80_StackPopWord
    CALL Z80_SetHL
    LD HL, 10
    JP Z80_AddTStates
Z80_OP_F1:
    CALL Z80_StackPopWord
    LD A, L
    LD (CPU_AF), A
    LD A, H
    LD (CPU_AF+1), A
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_C5:
    CALL Z80_GetBC
    EX DE, HL
    CALL Z80_StackPushWord
    LD HL, 11
    JP Z80_AddTStates
Z80_OP_D5:
    CALL Z80_GetDE
    EX DE, HL
    CALL Z80_StackPushWord
    LD HL, 11
    JP Z80_AddTStates
Z80_OP_E5:
    CALL Z80_GetHL
    EX DE, HL
    CALL Z80_StackPushWord
    LD HL, 11
    JP Z80_AddTStates
Z80_OP_F5:
    LD A, (CPU_AF)
    LD E, A
    LD A, (CPU_AF+1)
    LD D, A
    CALL Z80_StackPushWord
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_C3:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    CALL Z80_SetPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_C9:
    CALL Z80_StackPopWord
    CALL Z80_SetPC
    LD HL, 10
    JP Z80_AddTStates

Z80_OP_CD:
    CALL Z80_GetPC
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_GetPC
    INC HL
    INC HL
    EX DE, HL
    CALL Z80_StackPushWord
    POP HL
    CALL Z80_SetPC
    LD HL, 17
    JP Z80_AddTStates

Z80_OP_RST_Common:
    PUSH DE
    CALL Z80_GetPC
    EX DE, HL
    CALL Z80_StackPushWord
    POP HL
    CALL Z80_SetPC
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_C7:
    LD DE, $0000
    JP Z80_OP_RST_Common
Z80_OP_CF:
    LD DE, $0008
    JP Z80_OP_RST_Common
Z80_OP_D7:
    LD DE, $0010
    JP Z80_OP_RST_Common
Z80_OP_DF:
    LD DE, $0018
    JP Z80_OP_RST_Common
Z80_OP_E7:
    LD DE, $0020
    JP Z80_OP_RST_Common
Z80_OP_EF:
    LD DE, $0028
    JP Z80_OP_RST_Common
Z80_OP_F7:
    LD DE, $0030
    JP Z80_OP_RST_Common
Z80_OP_FF:
    LD DE, $0038
    JP Z80_OP_RST_Common

Z80_OP_D3:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    LD C, A
    LD A, (CPU_AF+1)
    LD B, A
    CALL Z80_IO_WriteByte
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_DB:
    CALL Z80_GetPC
    CALL MSXMemory_ReadByte
    PUSH AF
    CALL Z80_IncPC
    POP AF
    LD C, A
    LD A, (CPU_AF+1)
    LD B, A
    CALL Z80_IO_ReadByte
    LD (CPU_AF+1), A
    LD HL, 11
    JP Z80_AddTStates

Z80_OP_D9:
    CALL Z80_GetBC
    PUSH HL
    LD A, (CPU_BC_ALT)
    LD L, A
    LD A, (CPU_BC_ALT+1)
    LD H, A
    CALL Z80_SetBC
    POP HL
    LD A, L
    LD (CPU_BC_ALT), A
    LD A, H
    LD (CPU_BC_ALT+1), A

    CALL Z80_GetDE
    PUSH HL
    LD A, (CPU_DE_ALT)
    LD L, A
    LD A, (CPU_DE_ALT+1)
    LD H, A
    CALL Z80_SetDE
    POP HL
    LD A, L
    LD (CPU_DE_ALT), A
    LD A, H
    LD (CPU_DE_ALT+1), A

    CALL Z80_GetHL
    PUSH HL
    LD A, (CPU_HL_ALT)
    LD L, A
    LD A, (CPU_HL_ALT+1)
    LD H, A
    CALL Z80_SetHL
    POP HL
    LD A, L
    LD (CPU_HL_ALT), A
    LD A, H
    LD (CPU_HL_ALT+1), A

    LD HL, 4
    JP Z80_AddTStates

Z80_OP_E3:
    CALL Z80_GetSP
    CALL MSXMemory_ReadWord
    PUSH HL
    CALL Z80_GetHL
    PUSH HL
    CALL Z80_GetSP
    POP DE
    CALL MSXMemory_WriteWord
    POP HL
    CALL Z80_SetHL
    LD HL, 19
    JP Z80_AddTStates

Z80_OP_E9:
    CALL Z80_GetHL
    CALL Z80_SetPC
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_EB:
    CALL Z80_GetDE
    PUSH HL
    CALL Z80_GetHL
    CALL Z80_SetDE
    POP HL
    CALL Z80_SetHL
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_F3:
    XOR A
    LD (CPU_IFF1), A
    LD (CPU_IFF2), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_FB:
    LD A, 1
    LD (CPU_IFF1), A
    LD (CPU_IFF2), A
    LD HL, 4
    JP Z80_AddTStates

Z80_OP_F9:
    CALL Z80_GetHL
    CALL Z80_SetSP
    LD HL, 6
    JP Z80_AddTStates

Z80_OP_UNIMPLEMENTED:
    SCF
    RET

; ----------------------------------------------------------
; Handlers ALU Inmediatos ($C6, $CE, $D6, $DE, $E6, $EE, $F6, $FE)
; ----------------------------------------------------------
Z80_OP_C6:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_ADD
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_CE:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_ADC
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_D6:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_SUB
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_DE:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_SBC
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_E6:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_AND
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_EE:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_XOR
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_F6:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_OR
    LD HL, 7
    JP Z80_AddTStates

Z80_OP_FE:
    CALL Z80_GetImmByte
    LD E, A
    CALL Z80_ALU_CP
    LD HL, 7
    JP Z80_AddTStates

; ----------------------------------------------------------
; TABLA PRINCIPAL DE DECODIFICACIÓN Z80
; ----------------------------------------------------------
    ALIGN 4
Z80_DispatchTable:
    ; $00 - $0F
    DL Z80_OP_00, Z80_OP_01, Z80_OP_02, Z80_OP_03, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_07
    DL Z80_OP_08, Z80_OP_09, Z80_OP_0A, Z80_OP_0B, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_0F

    ; $10 - $1F
    DL Z80_OP_10, Z80_OP_11, Z80_OP_12, Z80_OP_13, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_17
    DL Z80_OP_18, Z80_OP_19, Z80_OP_1A, Z80_OP_1B, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_1F

    ; $20 - $2F
    DL Z80_OP_20, Z80_OP_21, Z80_OP_22, Z80_OP_23, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_27
    DL Z80_OP_28, Z80_OP_29, Z80_OP_2A, Z80_OP_2B, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_2F

    ; $30 - $3F
    DL Z80_OP_30, Z80_OP_31, Z80_OP_32, Z80_OP_33, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_Block00_LD_R_N, Z80_OP_37
    DL Z80_OP_38, Z80_OP_39, Z80_OP_3A, Z80_OP_3B, Z80_OP_Block00_INC_R, Z80_OP_Block00_DEC_R, Z80_OP_3E, Z80_OP_3F

    ; $40 - $4F (LD r, r')
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40

    ; $50 - $5F (LD r, r')
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40

    ; $60 - $6F (LD r, r')
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40

    ; $70 - $7F (LD r, r' excepto $76 HALT)
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_76,      Z80_OP_Block40
    DL Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40, Z80_OP_Block40

    ; $80 - $8F (ALU A, r)
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80

    ; $90 - $9F (ALU A, r)
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80

    ; $A0 - $AF (ALU A, r)
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80

    ; $B0 - $BF (ALU A, r)
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80
    DL Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80, Z80_OP_Block80

    ; $C0 - $CF
    DL Z80_OP_C0, Z80_OP_C1, Z80_OP_C2, Z80_OP_C3, Z80_OP_C4, Z80_OP_C5, Z80_OP_C6, Z80_OP_C7
    DL Z80_OP_C8, Z80_OP_C9, Z80_OP_CA, Z80_OP_CB_Dispatch, Z80_OP_CC, Z80_OP_CD, Z80_OP_CE, Z80_OP_CF

    ; $D0 - $DF
    DL Z80_OP_D0, Z80_OP_D1, Z80_OP_D2, Z80_OP_D3, Z80_OP_D4, Z80_OP_D5, Z80_OP_D6, Z80_OP_D7
    DL Z80_OP_D8, Z80_OP_D9, Z80_OP_DA, Z80_OP_DB, Z80_OP_DC, Z80_OP_DD_Dispatch, Z80_OP_DE, Z80_OP_DF

    ; $E0 - $EF
    DL Z80_OP_E0, Z80_OP_E1, Z80_OP_E2, Z80_OP_E3, Z80_OP_E4, Z80_OP_E5, Z80_OP_E6, Z80_OP_E7
    DL Z80_OP_E8, Z80_OP_E9, Z80_OP_EA, Z80_OP_EB, Z80_OP_EC, Z80_OP_ED_Dispatch, Z80_OP_EE, Z80_OP_EF

    ; $F0 - $FF
    DL Z80_OP_F0, Z80_OP_F1, Z80_OP_F2, Z80_OP_F3, Z80_OP_F4, Z80_OP_F5, Z80_OP_F6, Z80_OP_F7
    DL Z80_OP_F8, Z80_OP_F9, Z80_OP_FA, Z80_OP_FB, Z80_OP_FC, Z80_OP_FD_Dispatch, Z80_OP_FE, Z80_OP_FF
