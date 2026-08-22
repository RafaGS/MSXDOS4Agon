; ==========================================================
; MSXDOS4Agon - MSX-DOS High Level Emulator for Agon MOS
;
; msxdos: MSX-DOS Engine 
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

.ASSUME ADL=1
    ORG $040000

    JP _start

    ALIGN 64
    DB "MOS", 0, 1

_start:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    PUSH IX
    PUSH IY

    PUSH HL
    LD HL, msg_banner
    CALL PrintString
    POP HL

    CALL Run_MSXDOS

    POP IY
    POP IX
    POP HL
    POP DE
    POP BC
    POP AF

    ; --- TRAMPA FINAL: Si llega aquí, el emulador terminó ---
    EI
    LD HL, msg_fatal_exit
    CALL PrintString
.freeze_fatal:
    JR .freeze_fatal
    ; ---------------------------------------------------------

    RET
    
; ----------------------------------------------------------
; SPRINT 7.0 / 11.1: Universal .COM Loader & Environment
; ----------------------------------------------------------
Run_MSXDOS:
    ; 0. Salvar el puntero a los argumentos del MOS
    PUSH HL

    ; --- NUEVO: PINTAR LA PANTALLA TIPO MSX ---
    LD HL, msg_colors
    CALL PrintString
    ; ------------------------------------------
    ; --- AÑADIR BANNER DE MSX-DOS ---
    LD HL, msg_msxdos_banner
    CALL PrintString
    ; ------------------------------------------

    ; 1. Limpieza de RAM Virtual (Exactamente 65536 bytes)
    LD HL, MSX_RAM
    LD DE, MSX_RAM + 1
    XOR A
    LD (HL), A                  
    LD BC, 65535
    LDIR                        ; Propaga el cero

    ; --- INYECTAR DPBs MSX-DOS EN ZONA SEGURA (SANTUARIO $F100) ---
    LD HL, dpb_a
    LD DE, MSX_RAM + $F100      ; <-- BÚNKER DE VERDAD
    LD BC, 21
    LDIR
    
    LD HL, dpb_b
    LD DE, MSX_RAM + $F120      ; <-- BÚNKER DE VERDAD
    LD BC, 21
    LDIR

    ; --- LA LLAVE MAESTRA: NMBDRV ---
    LD A, 2
    LD (MSX_RAM + $F347), A     ; $F347 = NMBDRV (Número de unidades lógicas)    
    ; --------------------------------------------------------------

    ; 1.5 Recuperar puntero y Parsear la Línea de Comandos
    POP HL
    CALL Parse_CommandLine
    OR A
    JP NZ, .err_usage

    ; ----------------------------------------------------------
    ; 2. INICIALIZAR VECTORES DE PÁGINA CERO ($0000 y $0005)
    ; ----------------------------------------------------------
    ; $0000: HALT ($76) -> Salida limpia si el programa hace JP $0000 o RET
    LD A, 76h                   ; Opcode HALT (en lugar de 0C3h)
    LD (MSX_RAM + $0000), A
    
    ; $0005: JP $F000 (Indica TPA libre hasta $F000 = 60 KB de RAM)
    LD A, 0C3h                  ; Opcode JP
    LD (MSX_RAM + $0005), A
    XOR A
    LD (MSX_RAM + $0006), A    ; Low Byte ($00)
    LD A, 0F0h
    LD (MSX_RAM + $0007), A    ; High Byte ($F0) -> $F000

    ; 3. Inicializar Tabla Interna de Handles
    CALL HandleTable_Init

    ; 4. Construir FCBs e Iniciar Ejecución
    CALL Build_Default_FCBs

    LD HL, MSX_RAM
    LD DE, $0100
    ADD HL, DE
    EX DE, HL
    
    LD HL, filename_buffer
    LD BC, 0
    LD A, 01h
    RST.L 08h
    OR A
    JP NZ, .err_load

    CALL Z80_Reset
    LD HL, $0080
    LD (DMA_Address), HL
    XOR A
    LD (key_lookahead), A
    XOR A
    LD (CPU_IndexSel), A
    XOR A
    LD (console_esc_state), A

    LD HL, $F000
    CALL Z80_SetSP
    
    LD HL, $0100
    CALL Z80_SetPC

Resume_Step_Loop:                  ; punto de entrada global a .step_loop,
                                    ; para poder saltar aquí desde fuera del
                                    ; ámbito de Run_MSXDOS (p.ej. MSX_BDOS_Hook)
.step_loop:
    CALL Z80_Step
    
    CALL Z80_GetPC
    
    ; --- TRAMPA DE PÁGINA CERO ---
    LD A, H
    OR A                        ; ¿El PC está en $00xx?
    JR NZ, .check_bdos
    LD A, L
    CP 00h                      ; Ignorar $0000 (Salida limpia)
    JR Z, .check_bdos
    CP 05h                      ; Ignorar $0005 (Llamada BDOS)
    JR Z, .check_bdos
    CP 30h                      ; <-- NUEVO: Interceptar RST 30h
    JP Z, .handle_rst30    

    ; --- PUENTE DE SALIDA A MOS ---
    CP 01h                      ; ¿PC = $0001? (Comando 'basic' ejecutado)
    JP Z, .exit_to_mos
    ; ---------------------------------

    ; Si llega aquí, está ejecutando código BIOS/MSX. ¡Lo atrapamos!
    PUSH HL
    LD HL, msg_bios_trap
    CALL PrintString
    POP HL                      ; <-- CORREGIDO: Recuperamos HL intacto
    LD A, L                     ; <-- CORREGIDO: Pasamos el byte bajo (L) a A
    CALL PrintHexByte
    LD A, 1
    LD (CPU_HALT), A            ; Forzamos el fin del emulador
    JR .halt_ok
    ; -----------------------------

.check_bdos:
    LD DE, $0005
    OR A
    SBC HL, DE
    JR NZ, .not_bdos
    
    CALL MSX_BDOS_Hook

    JR .not_bdos                ; Salto preventivo para separar lógicas

.handle_rst30:
    ; ============================================================
    ; RST 30h / CALLF
    ; ============================================================

    CALL Z80_GetSP
    CALL MSXMemory_ReadWord
    ; HL = dirección de parámetros CALLF (ej. $0031)

    PUSH HL                     ; Guardamos el puntero a los parámetros

    INC HL
    CALL MSXMemory_ReadWord
    ; HL = destino BIOS solicitado

    ; ============================================================
    ; Dispatcher
    ; ============================================================

    LD A, H
    OR A
    JR NZ, .rst30_generic_pop   ; Si High byte != 00, no es de nuestra incumbencia aún

    LD A, L
    CP 0A2h
    JR Z, .rst30_chput          ; ¡Cazado CHPUT ($00A2)!

.rst30_generic_pop:
    POP HL                      ; Recuperamos el puntero a los parámetros
    JR .rst30_bypass            ; Y saltamos al bypass genérico


    ; ============================================================
    ; CHPUT = BIOS $00A2
    ; ============================================================

.rst30_chput:
    POP HL

    LD A, (CPU_AF + 1)
    CALL MSX_Console_PutChar

    INC HL
    INC HL
    INC HL
    CALL Z80_SetPC

    CALL Z80_GetSP
    INC HL
    INC HL
    CALL Z80_SetSP

    JP .not_bdos

    ; ============================================================
    ; Bypass genérico de CALLF
    ; ============================================================

.rst30_bypass:
    ; HL = dirección de parámetros

    INC HL
    INC HL
    INC HL
    CALL Z80_SetPC

    ; Pop de la dirección que dejó RST 30h en la pila virtual
    CALL Z80_GetSP
    INC HL
    INC HL
    CALL Z80_SetSP

    JP .not_bdos

.not_bdos:
    LD A, (CPU_HALT)
    OR A
    JP Z, .step_loop

    ; DEBUG: averiguar dónde estaba la CPU cuando se detuvo
    CALL Z80_GetPC
    PUSH HL
    EI
    LD HL, msg_halt_pc
    CALL PrintString
    POP HL
    CALL PrintHexWord

    ; --- TRAMPA: Congelar para poder leer el PC ---
.freeze_halt:
    JR .freeze_halt
    ; ----------------------------------------------

    JR .halt_ok

.halt_ok:
    LD HL, msg_pass
    CALL PrintString
    RET

.exit_to_mos:
    ; --- WARM BOOT (semántica CP/M 2.2): un .COM hijo ha terminado
    ;     limpiamente (JP $0000 -> ejecuta el HALT que dejamos ahí).
    ;     Recargamos COMMAND.COM fresco y reanudamos, en vez de congelar. ---
    EI
    CALL Print_ExitTrap_If_Debug

    LD HL, MSX_RAM
    LD DE, $0100
    ADD HL, DE
    EX DE, HL
    LD HL, filename_buffer
    LD BC, 0
    LD A, 01h
    RST.L 08h
    OR A
    JP NZ, .err_load

    CALL Z80_Reset
    LD HL, $0080
    LD (DMA_Address), HL
    XOR A
    LD (key_lookahead), A
    XOR A
    LD (CPU_IndexSel), A
    XOR A
    LD (console_esc_state), A

    LD HL, $F000
    CALL Z80_SetSP
    LD HL, $0100
    CALL Z80_SetPC

    JP .step_loop

.err_usage:
    LD HL, msg_usage
    CALL PrintString
    RET

Global_Err_Load:                   ; alias global de .err_load, para poder
                                    ; saltar aquí desde fuera de Run_MSXDOS
.err_load:
    LD HL, filename_buffer
    CALL PrintString
    LD HL, msg_fail_load
    CALL PrintString
    RET

; ----------------------------------------------------------
; PARSER DE LÍNEA DE COMANDOS
; ----------------------------------------------------------
Parse_CommandLine:
.skip_spaces:
    LD A, (HL)
    OR A
    JR Z, .no_args
    CP 13
    JR Z, .no_args
    CP 10
    JR Z, .no_args
    CP ' '
    JR NZ, .copy_filename
    INC HL
    JR .skip_spaces

.copy_filename:
    LD DE, filename_buffer
.copy_loop:
    LD A, (HL)
    OR A
    JR Z, .filename_done
    CP 13
    JR Z, .filename_done
    CP 10
    JR Z, .filename_done
    CP ' '
    JR Z, .filename_done
    
    LD (DE), A
    INC HL
    INC DE
    JR .copy_loop

.filename_done:
    XOR A
    LD (DE), A

    LD A, (filename_buffer)
    OR A
    JR Z, .no_args

    LD DE, MSX_RAM + $0081
    LD B, 0

.tail_loop:
    LD A, (HL)
    OR A
    JR Z, .tail_done
    CP 13
    JR Z, .tail_done
    CP 10
    JR Z, .tail_done
    
    LD (DE), A
    INC HL
    INC DE
    INC B
    LD A, B
    CP 127
    JR Z, .tail_done
    JR .tail_loop

.tail_done:
    LD HL, MSX_RAM + $0080
    LD (HL), B
    
    LD A, 13
    LD (DE), A
    XOR A
    RET

.no_args:
    LD A, 1
    RET

; ----------------------------------------------------------
; INYECTOR DE DEFAULT FCBs ($005C y $006C)
; ----------------------------------------------------------
Build_Default_FCBs:
    LD HL, MSX_RAM + $0081
    LD DE, MSX_RAM + $005C
    CALL Parse_Single_FCB
    LD DE, MSX_RAM + $006C
    CALL Parse_Single_FCB
    RET

Parse_Single_FCB:
    PUSH DE
    POP IY

    XOR A
    LD (IY+0), A
    
    PUSH IY
    POP DE
    INC DE
    LD A, ' '
    LD B, 11
.pfcb_clean_name:
    LD (DE), A
    INC DE
    DEC B
    JR NZ, .pfcb_clean_name
    
    XOR A
    LD B, 4
.pfcb_clean_rest:
    LD (DE), A
    INC DE
    DEC B
    JR NZ, .pfcb_clean_rest

.pfcb_skip_spaces:
    LD A, (HL)
    OR A
    RET Z
    CP 13
    RET Z
    CP ' '
    JR NZ, .pfcb_check_drive
    INC HL
    JR .pfcb_skip_spaces

.pfcb_check_drive:
    PUSH HL
    INC HL
    LD A, (HL)
    POP HL
    CP ':'
    JR NZ, .pfcb_parse_name
    
    LD A, (HL)
    CALL ToUpper
    SUB 'A' - 1
    LD (IY+0), A
    INC HL
    INC HL

.pfcb_parse_name:
    PUSH IY
    POP DE
    INC DE
    LD B, 8
.pfcb_name_loop:
    LD A, (HL)
    OR A
    JR Z, .pfcb_done
    CP 13
    JR Z, .pfcb_done
    CP ' '
    JR Z, .pfcb_done
    CP '.'
    JR Z, .pfcb_parse_ext
    
    CALL ToUpper
    LD (DE), A
    INC DE
    INC HL
    DEC B
    JR NZ, .pfcb_name_loop
    
.pfcb_skip_to_ext:
    LD A, (HL)
    OR A
    JR Z, .pfcb_done
    CP 13
    JR Z, .pfcb_done
    CP ' '
    JR Z, .pfcb_done
    CP '.'
    JR Z, .pfcb_parse_ext
    INC HL
    JR .pfcb_skip_to_ext

.pfcb_parse_ext:
    INC HL
    
    PUSH IY
    POP DE
    PUSH HL
    LD HL, 9
    ADD HL, DE
    EX DE, HL
    POP HL
    
    LD B, 3
.pfcb_ext_loop:
    LD A, (HL)
    OR A
    JR Z, .pfcb_done
    CP 13
    JR Z, .pfcb_done
    CP ' '
    JR Z, .pfcb_done
    
    CALL ToUpper
    LD (DE), A
    INC DE
    INC HL
    DEC B
    JR NZ, .pfcb_ext_loop

.pfcb_done:
.pfcb_skip_word:
    LD A, (HL)
    OR A
    RET Z
    CP 13
    RET Z
    CP ' '
    RET Z
    INC HL
    JR .pfcb_skip_word

ToUpper:
    CP 'a'
    RET C
    CP 'z'+1
    RET NC
    SUB 32
    RET

; ----------------------------------------------------------
; DESPACHADOR BDOS ($0005)
; ----------------------------------------------------------
MSX_BDOS_Hook:
    EI                          ; <-- NUEVO: Salva al Agon MOS del deadlock

    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL
    PUSH IX
    PUSH IY
    
    CALL Z80_GetBC
    LD A, L
   
    ; --- TRAZA DE ENTRADA ---
    PUSH AF
    CALL Debug_BDOS_Enter
    POP AF
    ; ------------------------
    CP 00h 
    JP Z, .bdos_00
    CP 01h 
    JP Z, .bdos_01
    CP 02h 
    JP Z, .bdos_02
    CP 06h
    JP Z, .bdos_06
    CP 08h
    JP Z, .bdos_08
    CP 09h 
    JP Z, .bdos_09
    CP 0Ah 
    JP Z, .bdos_0A
    CP 0Bh 
    JP Z, .bdos_0B
    CP 0Ch 
    JP Z, .bdos_0C
    CP 0Eh
    JP Z, .bdos_0E
    CP 0Fh 
    JP Z, .bdos_0F
    CP 10h 
    JP Z, .bdos_10
    CP 11h
    JP Z, .bdos_11
    CP 12h
    JP Z, .bdos_12
    CP 13h 
    JP Z, .bdos_13    
    CP 14h 
    JP Z, .bdos_14
    CP 15h 
    JP Z, .bdos_15
    CP 16h 
    JP Z, .bdos_16
    CP 17h 
    JP Z, .bdos_17
    CP 18h
    JP Z, .bdos_18
    CP 19h
    JP Z, .bdos_19
    CP 1Ah 
    JP Z, .bdos_1A
    CP 1Bh                      
    JP Z, .bdos_1B_1C           
    CP 1Ch                      
    JP Z, .bdos_1B_1C
    CP 1Fh                      ; Get DPB
    JP Z, .bdos_1F
    CP 21h                      ; <-- NUEVO: F_READRAND (CP/M clásico)
    JP Z, .bdos_21
    CP 26h                      ; <-- NUEVO: Random Block Write
    JP Z, .bdos_26              ; <-- NUEVO
    CP 27h
    JP Z, .bdos_27              ; <-- NUEVO: Random Block Read
    ; --- NUEVAS LLAMADAS DE FECHA Y HORA ---
    CP 2Ah
    JP Z, .bdos_2A
    CP 2Bh
    JP Z, .bdos_2B
    CP 2Ch
    JP Z, .bdos_2C
    CP 2Dh
    JP Z, .bdos_2D
    CP 5Ah                      ; <-- AÑADIR: Capturar llamada interna $5A
    JP Z, .bdos_5A
    CP 62h                      ; <-- NUEVO: _TERM (Terminate with error code)
    JP Z, .bdos_62

    ; Trampa no destructiva: código real de MSX-DOS para
    ; "Invalid MSX-DOS call" (.IBDOS = $DC), no un $FF genérico -
    ; así los programas que comprueban este código específico
    ; (p. ej. para detectar la versión de DOS) funcionan igual
    ; que en MSX-DOS real.
    PUSH AF
    LD A, (Debug_Enabled)
    OR A
    JR Z, .skip_unhandled_dbg
    LD HL, msg_unhandled_bdos
    CALL PrintString
    POP AF
    PUSH AF
    CALL PrintHexByte
    LD HL, msg_crlf
    CALL PrintString
.skip_unhandled_dbg:
    POP AF
    
    LD A, 0DCh
    LD (CPU_AF+1), A
    JP .bdos_return

; ------------------------------------------------------------
; 62h - _TERM: Terminate with error code.
; Igual que un JP $0000 limpio: en MSX-DOS real esta función NUNCA
; vuelve al programa. Reutilizamos el mismo warm boot que ya usamos
; para el HALT en $0000 tras un .COM hijo, en vez de caer en el
; manejador genérico de "no implementado" (que sí hace RET y deja
; al programa seguir ejecutando código pensado para no alcanzarse
; nunca).
; ------------------------------------------------------------
.bdos_62:
    CALL Print_ExitTrap_If_Debug

    LD HL, MSX_RAM
    LD DE, $0100
    ADD HL, DE
    EX DE, HL
    LD HL, filename_buffer
    LD BC, 0
    LD A, 01h
    RST.L 08h
    OR A
    JP NZ, Global_Err_Load

    CALL Z80_Reset
    LD HL, $0080
    LD (DMA_Address), HL
    XOR A
    LD (key_lookahead), A
    XOR A
    LD (CPU_IndexSel), A
    XOR A
    LD (console_esc_state), A

    LD HL, $F000
    CALL Z80_SetSP
    LD HL, $0100
    CALL Z80_SetPC

    JP Resume_Step_Loop

.bdos_00:
    ; --- Función 00h (_TERM0): "Program terminate", compatible con
    ;     CP/M y MSX-DOS 1. Igual que 62h (_TERM) y el HALT en $0000:
    ;     nunca vuelve al programa. Mismo warm boot ya validado. ---
    CALL Print_ExitTrap_If_Debug

    LD HL, MSX_RAM
    LD DE, $0100
    ADD HL, DE
    EX DE, HL
    LD HL, filename_buffer
    LD BC, 0
    LD A, 01h
    RST.L 08h
    OR A
    JP NZ, Global_Err_Load

    CALL Z80_Reset
    LD HL, $0080
    LD (DMA_Address), HL
    XOR A
    LD (key_lookahead), A
    XOR A
    LD (CPU_IndexSel), A
    XOR A
    LD (console_esc_state), A

    LD HL, $F000
    CALL Z80_SetSP
    LD HL, $0100
    CALL Z80_SetPC

    JP Resume_Step_Loop

.bdos_01:
.wait_key:
    CALL System_WaitKey
    LD (CPU_AF+1), A
    CP 1Bh 
    JP Z, .bdos_return
    PUSH AF 
    RST.L 10h 
    POP AF
    CP 0Dh 
    JP NZ, .bdos_return
    LD A, 0Ah 
    RST.L 10h
    JP .bdos_return

.bdos_02:
    CALL Z80_GetDE
    LD A, L
    CALL MSX_Console_PutChar
    JP .bdos_return

.bdos_06:
    CALL Z80_GetDE
    LD A, L
    CP 0FFh
    JR Z, .bdos_06_input

    CALL MSX_Console_PutChar
    JP .bdos_return

.bdos_06_input:
    LD A, (key_lookahead)
    OR A
    JR NZ, .bdos_06_has_key
    LD A, 00h
    RST.L 08h
    OR A
    JR Z, .bdos_06_no_key

.bdos_06_has_key:
    PUSH AF
    XOR A
    LD (key_lookahead), A
    POP AF
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_06_no_key:
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_08:
    CALL System_WaitKey
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_09:
    CALL Z80_GetDE
.print_loop:
    CALL MSXMemory_ReadByte 
    CP '$' 
    JP Z, .bdos_return

    PUSH HL 
    CALL MSX_Console_PutChar
    POP HL

    INC HL 
    JR .print_loop

.bdos_0B:
    LD A, (key_lookahead)
    OR A
    JR NZ, .has_key
    LD A, 00h
    RST.L 08h
    OR A
    JR Z, .no_key
    LD (key_lookahead), A
.has_key:
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return
.no_key:
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_0C:
    ; Get Version (Engañamos a COMMAND.COM diciendo que somos CP/M 2.2 / MSX-DOS 1)
    LD HL, 0022h
    LD (CPU_HL), HL
    LD A, 22h
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_0E:
    CALL Z80_GetDE
    LD A, L                     ; L contiene la unidad (0=A, 1=B)
    CP 0FFh                     ; ¿Es un query interno?
    JR Z, .bdos_0E_skip
    
    ; --- EL SECRETO DE CP/M: ACTUALIZAR $0004 ---
    PUSH HL
    LD HL, MSX_RAM + $0004
    LD (HL), A                  ; Inyectamos 0=A o 1=B en la memoria cruda
    POP HL
    ; --------------------------------------------
    
    INC A                       ; Convertimos para nuestro formato interno (1=A, 2=B)
    LD (current_drive), A
    
.bdos_0E_skip:
    LD A, 2                     ; Le recordamos que hay 2 discos
    LD (CPU_AF+1), A
    LD HL, 2
    LD (CPU_HL), HL
    JP .bdos_return

.bdos_18:
    ; Get Login Vector (Bits 0 y 1 a '1' = Discos A y B válidos)
    LD HL, 3
    LD (CPU_HL), HL
    LD A, 3
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_19:
    ; Get Current Disk
    LD A, (current_drive)
    DEC A
    LD (CPU_AF+1), A            ; Devolver en A
    LD HL, 0
    LD L, A
    LD (CPU_HL), HL             ; Devolver en L
    JP .bdos_return

.bdos_11:
    CALL Z80_GetDE
    LD (current_search_fcb), HL     ; Guardamos el FCB para el filtro interno
    
    ; ============================================================
    ; DEBUG: FCB completo de SEARCH FIRST
    ; ============================================================
    ;PUSH HL

    ;LD HL, msg_search_fcb
    ;CALL PrintString

    ;POP HL
    PUSH HL

    ; HL = dirección virtual del FCB
    ;CALL Z80_TruncateHL
    ;LD DE, MSX_RAM
    ;ADD HL, DE

    ;LD B, 12
.dump_search_fcb:
    ;LD A, (HL)
    ;CALL PrintHexByte

    ;LD A, ' '
    ;RST.L 10h

    ;INC HL
    ;DJNZ .dump_search_fcb

    ;LD HL, msg_crlf
    ;CALL PrintString

    ;POP HL
    ; ============================================================

    CALL MSX_FS_SearchFirst
    OR A
    JP NZ, .search_fail
    
    LD A, 1
    LD (search_active), A
    JP .format_dma_and_return

.bdos_12:
    ; 1. Failsafe: No buscar si no hubo Search First previo
    LD A, (search_active)
    OR A
    JP Z, .search_fail

    ; 2. Delegar en el Backend
    CALL MSX_FS_SearchNext
    OR A
    JP NZ, .search_fail
    
    JP .format_dma_and_return

; ==========================================================
; CAPA DE ABSTRACCIÓN: MSX_FS_BACKEND
; ==========================================================
MSX_FS_SearchFirst:
    LD HL, fat_dir_obj
    LD BC, 64
    CALL Clear_Buffer
    LD HL, fat_filinfo
    LD BC, 300
    CALL Clear_Buffer

    ; --- ELEGIR CARPETA DE BÚSQUEDA ---
    LD HL, (current_search_fcb)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD A, (HL)                  ; Leer Drive (Byte 0) del FCB de búsqueda
    AND 7Fh                     ; <-- ¡CLAVE! Limpiamos el Bit 7 (Flag especial de MSX-DOS)
    OR A
    JR NZ, .got_s_drive
    LD A, (current_drive)       ; Unidad actual por defecto
.got_s_drive:
    CP 2
    JR Z, .s_drive_b
.s_drive_a:
    LD BC, str_path_a           ; Carpeta /msxdos/a/
    JR .do_find
.s_drive_b:
    LD BC, str_path_b           ; Carpeta /msxdos/b/
.do_find:

    ; --- INICIO DEL CHIVATO DE ENRUTAMIENTO ---
    ;PUSH BC                     ; Guardamos BC (que contiene la ruta física)
    
    ;LD HL, msg_search_path
    ;CALL PrintString
    
    ;POP HL                      ; Pasamos la ruta a HL para imprimirla
    ;PUSH HL                     ; Y la volvemos a guardar en la pila
    ;CALL PrintString            ; Imprimimos "/msxdos/a" o "/msxdos/b"
    
    ;LD HL, msg_crlf
    ;CALL PrintString
    
    ;POP BC                      ; Restauramos BC intacto para la llamada a MOS
    ; --- FIN DEL CHIVATO ---

    LD IX, str_star             ; FatFs: ¡Tráemelos TODOS!
    LD HL, fat_dir_obj
    LD DE, fat_filinfo
    LD A, 94h
    RST.L 08h

    ; ============================================================
    ; DEBUG: FRESULT real de MOS $94
    ; ============================================================
    ;PUSH AF                     ; Guardar FRESULT original

    ;LD HL, msg_mos94
    ;CALL PrintString

    ;POP AF                      ; Recuperar FRESULT en A
    ;PUSH AF                     ; Volver a guardarlo
    ;CALL PrintHexByte           ; Imprimir A (PrintHexByte lo preserva internamente)

    ;LD HL, msg_crlf
    ;CALL PrintString            ; ¡ATENCIÓN! PrintString destruye A

    ;POP AF                      ; Recuperamos el FRESULT original intacto
    ; ============================================================

    OR A
    RET NZ

.check_first:
    LD A, (fat_filinfo + 9)
    OR A
    JR NZ, .eval_first
    LD A, (fat_filinfo + 22)
    OR A
    JR NZ, .eval_first
    LD A, 0FFh                  ; Directorio vacío
    RET

.eval_first:
    CALL Check_FCB_Match        ; ¿Pasa nuestro filtro MSX-DOS?
    JR Z, .match_ok
    JR MSX_FS_SearchNext        ; Si no pasa, pedimos el siguiente automáticamente

.match_ok:
    XOR A
    RET

MSX_FS_SearchNext:
.next_loop:
    LD HL, fat_dir_obj
    LD DE, fat_filinfo
    LD A, 95h
    RST.L 08h
    OR A
    RET NZ

    LD A, (fat_filinfo + 9)
    OR A
    JR NZ, .eval_next
    LD A, (fat_filinfo + 22)
    OR A
    JR NZ, .eval_next
    LD A, 0FFh                  ; Fin de directorio
    RET

.eval_next:
    CALL Check_FCB_Match        ; ¿Pasa nuestro filtro?
    JR Z, .match_ok_next
    JR .next_loop               ; Si no, iteramos hasta que FatFs nos dé uno válido

.match_ok_next:
    XOR A
    RET

; ==========================================================
; MOTOR DE FILTRADO MSX-DOS EXACTO
; ==========================================================
Check_FCB_Match:
    ; 1. Extraer nombre puro devuelto por el MOS
    LD HL, fat_filinfo + 9
    LD A, (HL)
    OR A
    JR NZ, .got_name
    LD HL, fat_filinfo + 22
.got_name:
    
    ; 2. Expandirlo a 11 caracteres con espacios (Formato MSX)
    PUSH HL
    LD HL, fat_filename
    LD B, 11
    LD A, ' '
.fill_spc:
    LD (HL), A
    INC HL
    DJNZ .fill_spc
    POP HL
    
    LD DE, fat_filename
    LD B, 8
.copy_name:
    LD A, (HL)
    OR A
    JR Z, .name_done_pad
    CP '.'
    JR Z, .do_ext
    CALL ToUpper                ; Convertir todo a MAYÚSCULAS
    LD (DE), A
    INC HL
    INC DE
    DJNZ .copy_name
    
.skip_to_ext:
    LD A, (HL)
    OR A
    JR Z, .name_done_pad
    CP '.'
    JR Z, .do_ext
    INC HL
    JR .skip_to_ext
    
.do_ext:
    INC HL
    LD DE, fat_filename + 8
    LD B, 3
.copy_ext:
    LD A, (HL)
    OR A
    JR Z, .name_done_pad
    CALL ToUpper                ; Convertir extensión a MAYÚSCULAS
    LD (DE), A
    INC HL
    INC DE
    DJNZ .copy_ext

.name_done_pad:
    
    ; 3. Comparar nuestro nombre normalizado con el FCB original
    LD HL, (current_search_fcb)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    INC HL                      ; Saltar el Drive, ir al Nombre (Offset 1)
    
    LD DE, fat_filename
    LD B, 11
.cmp_loop:
    LD A, (HL)
    CP '?'
    JR Z, .cmp_next             ; MSX-DOS: '?' coincide con CUALQUIER letra
    
    LD C, A
    LD A, (DE)
    CP C
    JR NZ, .cmp_fail            ; Si no es igual, rechazamos este archivo
    
.cmp_next:
    INC HL
    INC DE
    DJNZ .cmp_loop
    
    XOR A                       ; Z Flag = Coincidencia perfecta
    RET
    
.cmp_fail:
    OR 0FFh                     ; NZ Flag = No coincide
    RET

.format_dma_and_return:
    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    PUSH HL
    POP IY

    ; Limpiar DMA
    PUSH IY
    POP HL
    LD B, 32
.clear_dma:
    LD (HL), 0
    INC HL
    DEC B
    JR NZ, .clear_dma

    ; Copiar Drive
    LD HL, (current_search_fcb)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD A, (HL)
    LD (IY+0), A

    ; Rellenar zona de Nombre con Espacios
    PUSH IY
    POP DE
    INC DE
    LD B, 11
    LD A, ' '
.fill_spaces_dma:
    LD (DE), A
    INC DE
    DEC B
    JR NZ, .fill_spaces_dma

    ; Extraer Nombre (Corto o Largo)
    LD HL, fat_filinfo + 9
    LD A, (HL)
    OR A
    JR NZ, .got_fname_ptr
    LD HL, fat_filinfo + 22     ; Fallback al offset 22 (LFN) si el corto está vacío
.got_fname_ptr:
    PUSH IY
    POP DE
    INC DE
    LD B, 8
.copy_dma_fname:
    LD A, (HL)
    OR A
    JR Z, .fname_done
    CP '.'
    JR Z, .fname_ext
    CALL ToUpper
    LD (DE), A
    INC HL
    INC DE
    DEC B
    JR NZ, .copy_dma_fname
    
.skip_to_ext_dma:
    LD A, (HL)
    OR A
    JR Z, .fname_done
    CP '.'
    JR Z, .fname_ext
    INC HL
    JR .skip_to_ext_dma

.fname_ext:
    INC HL
    PUSH IY
    POP DE
    PUSH HL
    LD HL, 9
    ADD HL, DE
    EX DE, HL
    POP HL
    LD B, 3
.copy_dma_fext:
    LD A, (HL)
    OR A
    JR Z, .fname_done
    CALL ToUpper
    LD (DE), A
    INC HL
    INC DE
    DEC B
    JR NZ, .copy_dma_fext

.fname_done:
    ; Copiar tamaño de archivo (offset 0 a DMA+28)
    LD HL, fat_filinfo
    PUSH IY
    POP DE
    PUSH HL
    LD HL, 28
    ADD HL, DE
    EX DE, HL
    POP HL
    LD B, 4
.copy_fsize:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    DEC B
    JR NZ, .copy_fsize

.search_success:
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.search_fail:
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_1A:
    CALL Z80_GetDE
    LD (DMA_Address), HL
    JP .bdos_return

.bdos_1B_1C:
    ; 1Bh (Current) y 1Ch (Specific) - Get Allocation Info MSX-DOS
    CALL Z80_GetDE
    LD A, L                     ; E contiene la unidad solicitada (0=default, 1=A, 2=B)
    OR A
    JR NZ, .chk_drive_1b
    LD A, (current_drive)
.chk_drive_1b:
    CP 2
    JR Z, .is_drive_b_1b
.is_drive_a_1b:
    LD HL, $F100                ; IX = DPB de A: (¡Santuario!)
    JR .set_dpb_1b
.is_drive_b_1b:
    LD HL, $F120                ; IX = DPB de B: (¡Santuario!)
.set_dpb_1b:
    LD (CPU_IX), HL
    
    LD HL, 0
    LD (CPU_IY), HL

    ; Configurar el resto de parámetros (720KB 2DD)
    LD A, 2                     
    LD (CPU_AF+1), A
    LD HL, 512                  
    LD (CPU_BC), HL
    LD HL, 714                  
    LD (CPU_DE), HL
    LD HL, 714                  
    LD (CPU_HL), HL

    JP .bdos_return

.bdos_1F:
    ; Función 1Fh (Get DPB CP/M). MSX-DOS apenas la usa, la dejamos pasiva.
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

; ------------------------------------------------------------
; 21h - F_READRAND: lectura aleatoria clásica de CP/M 2.2. Un
; registro de tamaño fijo (FCB+14..15, 128 si es 0), posicionado
; según el registro aleatorio del FCB (+33..35), hacia DMA_Address.
; Distinta de 26h/27h (bloques MSX-DOS extendidos) - esta es la que
; usan programas CP/M "clásicos" (p.ej. PMEXT.COM).
;
; Al ser una función nueva (nada dependía antes de su comportamiento),
; es segura para incluir el seek con mos_flseek desde el principio -
; a diferencia del intento anterior en 26h/27h, que sí tenían
; llamantes internos (el cargador de COMMAND.COM) con FCBs no
; necesariamente inicializados.
; ------------------------------------------------------------
.bdos_21:
    CALL Z80_GetDE
    PUSH HL
    POP IX

    PUSH IX
    POP HL
    LD DE, 25
    ADD HL, DE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD A, (HL)
    OR A
    JR NZ, .rr_have_handle
    LD A, 6                      ; sin handle abierto: código de error CP/M
    LD (CPU_AF+1), A
    JP .bdos_return
.rr_have_handle:
    LD (RR_Handle), A

    PUSH IX
    POP HL
    LD DE, 14
    ADD HL, DE
    CALL MSXMemory_ReadWord
    LD A, H
    OR L
    JR NZ, .rr_recsize_ok
    LD HL, 128
.rr_recsize_ok:
    LD (RB_RecSize), HL

    PUSH IX
    POP HL
    LD DE, 33
    ADD HL, DE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD C, (HL)
    INC HL
    LD B, (HL)                  ; BC = registro aleatorio (16 bits bajos)

    LD DE, (RB_RecSize)
    LD HL, 0
    LD A, 16
.rr_mul_loop:
    ADD HL, HL
    SLA C
    RL B
    JR NC, .rr_mul_skip
    ADD HL, DE
.rr_mul_skip:
    DEC A
    JR NZ, .rr_mul_loop
                                 ; HL = offset en bytes para el seek

    LD A, (RR_Handle)
    LD C, A
    LD B, 0
    LD E, 0                     ; byte alto del offset (asumimos <16M)
    LD A, 1Ch                   ; mos_flseek
    RST.L 08h

    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE

    LD DE, (RB_RecSize)

    LD A, (RR_Handle)
    LD C, A
    LD B, 0

    LD A, 1Ah                   ; mos_fread
    RST.L 08h

    ; --- VACUNA ADL: Forzar DE a 16 bits puros ---
    LD A, E
    LD E, A
    LD A, D
    LD D, A
    LD (RR_BytesRead), DE

    LD A, D
    OR E
    JR NZ, .rr_check_partial

    ; --- nada leído: registro más allá de EOF -> A=1, buffer a cero ---
    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD BC, (RB_RecSize)
.rr_zero_loop:
    LD A, B
    OR C
    JR Z, .rr_zero_done
    XOR A
    LD (HL), A
    INC HL
    DEC BC
    JR .rr_zero_loop
.rr_zero_done:
    LD A, 1
    LD (CPU_AF+1), A
    JP .bdos_return

.rr_check_partial:
    ; --- lectura parcial: rellenar el resto del registro con ceros
    ;     ("dato no escrito", convención CP/M para random I/O) ---
    LD HL, (RB_RecSize)
    LD DE, (RR_BytesRead)
    OR A
    SBC HL, DE
    JR Z, .rr_full

    PUSH HL
    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, (RR_BytesRead)
    ADD HL, DE
    POP BC
.rr_pad_loop:
    LD A, B
    OR C
    JR Z, .rr_full
    XOR A
    LD (HL), A
    INC HL
    DEC BC
    JR .rr_pad_loop

.rr_full:
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

; ==========================================================
; EL NUEVO MOTOR DE ARCHIVOS MSX-DOS (LECTURA/ESCRITURA MOS)
; ==========================================================
.bdos_0F:
    CALL Z80_GetDE
    PUSH HL 
    POP IX

.normal_open:
    CALL FCB_To_FatFilename

    ; --- DEBUG TEMPORAL: mostrar la ruta física resuelta para este OPEN ---
    PUSH AF
    PUSH HL
    PUSH DE
    LD A, (Debug_Enabled)
    OR A
    JR Z, .skip_openpath_dbg
    LD HL, msg_dbg_path
    CALL PrintString
    LD HL, fat_filename
    CALL PrintString
    LD HL, msg_dbg_nl
    CALL PrintString
.skip_openpath_dbg:
    POP DE
    POP HL
    POP AF
    ; --- FIN DEBUG TEMPORAL ---

    ; --- RESTAURADO A TU CÓDIGO ORIGINAL (HL=Buffer, DE=Ruta) ---
    LD HL, fat_filinfo
    LD DE, fat_filename
    LD A, 96h                   ; ffs_stat
    RST.L 08h

    LD HL, fat_filename
    LD C, 01h                   
    LD A, 0Ah                   ; mos_fopen
    RST.L 08h
    OR A
    JR Z, .open_err
    
    PUSH AF
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    PUSH HL
    LD DE, 25
    ADD HL, DE
    POP DE
    POP AF                      
    LD (HL), A                  
    
    PUSH DE
    POP HL
    PUSH HL
    LD BC, 12
    ADD HL, BC
    LD (HL), 0
    POP HL
    PUSH HL
    LD BC, 32
    ADD HL, BC
    LD (HL), 0
    POP HL

    ; --- NUEVO: poner a cero el registro aleatorio (+33..35) al abrir,
    ;     como exige la convención CP/M/MSX-DOS - un FCB recién abierto
    ;     debe arrancar en el registro 0. Sin esto, un FCB reutilizado
    ;     internamente (p.ej. el del propio cargador de COMMAND.COM)
    ;     puede tener basura ahí y el seek de 26h/27h saltaría a una
    ;     posición equivocada. ---
    PUSH HL
    LD BC, 33
    ADD HL, BC
    LD (HL), 0
    INC HL
    LD (HL), 0
    INC HL
    LD (HL), 0
    POP HL

    PUSH HL
    LD BC, 14
    ADD HL, BC
    LD (HL), 80h
    INC HL
    LD (HL), 00h
    POP HL

    LD BC, 16
    ADD HL, BC
    EX DE, HL
    LD HL, fat_filinfo          
    LD B, 4
.copy_fsize_open:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    DEC B
    JR NZ, .copy_fsize_open
    
    XOR A                       
    LD (CPU_AF+1), A
    JP .bdos_return

.open_err:
    LD A, 0FFh                  
    LD (CPU_AF+1), A
    JP .bdos_return


.bdos_10:
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 25
    ADD HL, DE
    LD BC, 0                    
    LD C, (HL)                  
    
    LD A, 0Bh                   ; mos_fclose
    RST.L 08h
    
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_14:
    CALL Z80_GetDE
    PUSH HL
    POP IX

    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 25
    ADD HL, DE
    LD BC, 0                    
    LD C, (HL)
    
    LD A, C
    OR A
    JP Z, .read_eof

    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE                  

    LD DE, 128                  
    LD A, 1Ah                   ; mos_fread
    RST.L 08h
       
    ; --- VACUNA ADL: Forzar DE a 16 bits puros ---
    PUSH HL
    LD HL, 0
    LD L, E
    LD H, D
    EX DE, HL
    POP HL
    ; ---------------------------------------------
   
    ; --- EL MOS DEVUELVE BYTES REALES EN DE ---
    LD A, D
    OR E
    JP Z, .read_eof             

    LD A, D
    OR A
    JR NZ, .seq_read_full
    LD A, E
    CP 128
    JR Z, .seq_read_full

    ; Relleno EOF
    PUSH DE                     
    
    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD BC, MSX_RAM
    ADD HL, BC
    
    POP BC                      ; BC = bytes leídos (DE transferido)
    ADD HL, BC                  ; HL = destino del relleno
    
    LD A, 128
    SUB C
    LD B, A                     ; B = bytes a rellenar
    LD A, 1Ah                   ; EOF
.pad_seq_loop:
    LD (HL), A
    INC HL
    DJNZ .pad_seq_loop

.seq_read_full:
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 32
    ADD HL, DE
    INC (HL)                    

    XOR A                       
    LD (CPU_AF+1), A
    JP .bdos_return

.read_eof:
    LD A, 01h                   
    LD (CPU_AF+1), A
    JP .bdos_return


.bdos_15:
    CALL Z80_GetDE
    PUSH HL
    POP IX

    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 25
    ADD HL, DE
    LD BC, 0                    
    LD C, (HL)

    LD A, C
    OR A
    JP Z, .write_seq_err

    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE

    LD DE, 128
    LD A, 1Bh                   ; mos_fwrite
    RST.L 08h

    ; --- VACUNA ADL: Forzar DE a 16 bits puros ---
    PUSH HL
    LD HL, 0
    LD L, E
    LD H, D
    EX DE, HL
    POP HL
    ; ---------------------------------------------

    ; --- EL MOS DEVUELVE BYTES REALES EN DE ---
    LD A, D
    OR E
    JR Z, .write_seq_err
    
    LD A, D
    OR A
    JR NZ, .seq_write_full
    LD A, E
    CP 128
    JR NZ, .write_seq_err

.seq_write_full:
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 32
    ADD HL, DE
    INC (HL)

    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.write_seq_err:
    LD A, 01h
    LD (CPU_AF+1), A
    JP .bdos_return


.bdos_16:
    CALL Z80_GetDE
    PUSH HL
    POP IX
    CALL FCB_To_FatFilename
    
    LD HL, fat_filename
    LD C, 0Ah                   
    LD A, 0Ah                   
    RST.L 08h
    OR A
    JP Z, .create_err
    
    PUSH AF
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    PUSH HL
    LD DE, 25
    ADD HL, DE
    POP DE
    POP AF
    LD (HL), A                  
    
    PUSH DE
    POP HL
    PUSH HL
    LD BC, 12
    ADD HL, BC
    LD (HL), 0
    POP HL
    PUSH HL
    LD BC, 32
    ADD HL, BC
    LD (HL), 0
    POP HL
    PUSH HL
    LD BC, 14
    ADD HL, BC
    LD (HL), 80h
    INC HL
    LD (HL), 00h
    POP HL
    PUSH HL
    LD BC, 33
    ADD HL, BC
    LD (HL), 0
    INC HL
    LD (HL), 0
    INC HL
    LD (HL), 0
    POP HL
    PUSH HL
    LD BC, 16
    ADD HL, BC
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A
    POP HL

    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.create_err:
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_17:
    ; ============================================================
    ; BDOS $17 - RENAME FILE
    ;
    ; DE -> FCB
    ;
    ; FCB + 1..11   = nombre antiguo
    ; FCB + 17..27  = nombre nuevo
    ;
    ; MOS 3:
    ;   ffs_rename = $98
    ;   HL = source path
    ;   DE = destination path
    ;   A  = FRESULT
    ; ============================================================

    ; ------------------------------------------------------------
    ; 1. Obtener dirección virtual del FCB original
    ; ------------------------------------------------------------
    CALL Z80_GetDE
    PUSH HL
    POP IX                      ; IX = FCB virtual

    ; ------------------------------------------------------------
    ; 2. Convertir OLD NAME
    ;    FCB original ya está en IX
    ;    -> fat_filename = /msxdos/<drive>/<oldname>
    ; ------------------------------------------------------------
    CALL FCB_To_FatFilename

    ; Copiar la ruta antigua a rename_src
    LD HL, fat_filename
    LD DE, rename_src
.rename_copy_src:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    OR A
    JR NZ, .rename_copy_src

    ; ------------------------------------------------------------
    ; 3. Construir directamente la ruta DESTINO en fat_filename
    ; ------------------------------------------------------------

    LD IY, fat_filename

    ; ------------------------------------------------------------
    ; Drive del FCB original
    ; ------------------------------------------------------------
    PUSH IX
    POP HL
    CALL MSXMemory_ReadByte
    OR A
    JR NZ, .rename_have_drive

    LD A, (current_drive)

.rename_have_drive:
    CP 2
    JR Z, .rename_dst_b

    ; A:
    LD HL, str_path_a
    JR .rename_copy_dst_path

.rename_dst_b:
    ; B:
    LD HL, str_path_b

.rename_copy_dst_path:
    LD A, (HL)
    OR A
    JR Z, .rename_dst_slash

    CALL ToLower
    LD (IY), A
    INC IY
    INC HL
    JR .rename_copy_dst_path

.rename_dst_slash:
    LD A, '/'
    LD (IY), A
    INC IY

    ; ------------------------------------------------------------
    ; Nombre nuevo = FCB + 17
    ; ------------------------------------------------------------
    PUSH IX
    POP HL
    LD BC, 17
    ADD HL, BC

    LD B, 8

.rename_copy_newname:
    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .rename_dst_ext

    CALL ToLower
    LD (IY), A
    INC IY
    INC HL
    DJNZ .rename_copy_newname

.rename_skip_newname:
    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .rename_dst_ext
    INC HL
    JR .rename_skip_newname

.rename_dst_ext:
    ; Saltamos a la posición de extensión:
    ; FCB+17+8 = FCB+25
    PUSH IX
    POP HL
    LD BC, 25
    ADD HL, BC

    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .rename_dst_no_ext

    LD A, '.'
    LD (IY), A
    INC IY

    LD B, 3

.rename_copy_newext:
    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .rename_dst_no_ext

    CALL ToLower
    LD (IY), A
    INC IY
    INC HL
    DJNZ .rename_copy_newext

.rename_dst_no_ext:
    XOR A
    LD (IY), A

    ; ------------------------------------------------------------
    ; 4. MOS 3: rename
    ; ------------------------------------------------------------



    ; ------------------------------------------------------------
    ; 5. MOS 3 ffs_rename
    ;
    ; HL = source
    ; DE = destination
    ; ------------------------------------------------------------

    LD HL, rename_src
    LD DE, fat_filename
    LD A, 06h

PUSH AF
PUSH HL
PUSH DE

LD A, (Debug_Enabled)
OR A
JR Z, .skip_ren_dbg

LD HL,msg_dbg_rename_src
CALL PrintString
LD HL,rename_src
CALL PrintString

LD HL,msg_dbg_rename_dst
CALL PrintString
LD HL,fat_filename
CALL PrintString

LD HL,msg_dbg_nl
CALL PrintString

.skip_ren_dbg:
POP DE
POP HL
POP AF

    RST.L 08h

    ; A = FRESULT
    OR A
    JR Z, .rename_ok

    ; Error MSX-DOS RENAME
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

.rename_ok:
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_26:
    CALL Z80_GetHL
    PUSH HL                     ; [0] bloques pedidos
    
    CALL Z80_GetDE
    PUSH HL
    POP IX

    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 25
    ADD HL, DE
    LD BC, 0
    LD C, (HL)

    LD A, C
    OR A
    JP Z, .write_blk_err

    PUSH BC
    POP IY                      

    PUSH IX
    POP HL
    LD DE, 14
    ADD HL, DE
    CALL MSXMemory_ReadWord
    EX DE, HL                   

    LD A, D
    OR E
    JR NZ, .rs_ok_wr
    LD DE, 128
.rs_ok_wr:
    LD (RB_RecSize), DE

    POP BC                      
    PUSH BC                     ; [0]

    LD HL, 0
    LD A, 16
.mul_loop_wr:
    ADD HL, HL
    SLA C
    RL B
    JR NC, .mul_skip_wr
    ADD HL, DE
.mul_skip_wr:
    DEC A
    JR NZ, .mul_loop_wr

    PUSH HL                     ; [1] bytes pedidos

    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE                  
    
    POP DE                      
    PUSH DE                     ; [1]

    PUSH IY
    POP BC                      
    LD B, 0                     

    LD A, 1Bh                   ; mos_fwrite
    RST.L 08h

    ; --- VACUNA ADL: Forzar DE a 16 bits puros ---
    PUSH HL
    LD HL, 0
    LD L, E
    LD H, D
    EX DE, HL
    POP HL
    ; ---------------------------------------------

    ; --- CORRECCIÓN VITAL: EXTRAER 'DE' REAL ---
    POP HL                      ; [1] Recuperamos pedidos en HL
    PUSH HL                     ; [1]
    PUSH DE                     ; [2] Guardamos leídos reales (DE) en la pila

    LD HL, (RB_RecSize)
    EX DE, HL                   
    CALL Div16_HL_DE            
    
    LD (CPU_HL), HL             

    PUSH IX
    POP HL
    LD DE, 33
    ADD HL, DE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE

    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD C, (HL)

    LD A, (CPU_HL+0)            
    ADD A, E
    LD E, A
    LD A, (CPU_HL+1)            
    ADC A, D
    LD D, A
    JR NC, .no_carry_rr_wr
    INC C
.no_carry_rr_wr:
    LD (HL), C
    DEC HL
    LD (HL), D
    DEC HL
    LD (HL), E

    POP DE                      ; [2] DE = reales
    POP HL                      ; [1] HL = pedidos
    POP BC                      ; [0]
    
    OR A
    SBC HL, DE                  
    JR NZ, .partial_or_err_wr
    
    XOR A                       
    LD (CPU_AF+1), A
    JP .bdos_return

.partial_or_err_wr:
    LD A, 01h                   
    LD (CPU_AF+1), A
    JP .bdos_return

.write_blk_err:
    POP HL                      
    LD HL, 0
    LD (CPU_HL), HL             
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return


.bdos_27:
    CALL Z80_GetHL
    PUSH HL                     ; [0] bloques pedidos
    
    CALL Z80_GetDE
    PUSH HL
    POP IX                      

    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD DE, 25
    ADD HL, DE
    LD BC, 0
    LD C, (HL)                  

    LD A, C
    OR A
    JP Z, .read_blk_err

    PUSH BC
    POP IY                      

    PUSH IX
    POP HL
    LD DE, 14
    ADD HL, DE
    CALL MSXMemory_ReadWord
    EX DE, HL                   

    LD A, D
    OR E
    JR NZ, .rs_ok
    LD DE, 128
.rs_ok:
    LD (RB_RecSize), DE

    POP BC                      
    PUSH BC                     ; [0]

    LD HL, 0
    LD A, 16
.mul_loop:
    ADD HL, HL
    SLA C
    RL B
    JR NC, .mul_skip
    ADD HL, DE
.mul_skip:
    DEC A
    JR NZ, .mul_loop

    PUSH HL                     ; [1] bytes pedidos

    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE                  
    
    POP DE                      
    PUSH DE                     ; [1]

    PUSH IY
    POP BC                      
    LD B, 0                     

    LD A, 1Ah                   ; mos_fread
    RST.L 08h

    ; --- VACUNA ADL: Forzar DE a 16 bits puros ---
    PUSH HL
    LD HL, 0
    LD L, E
    LD H, D
    EX DE, HL
    POP HL
    ; ---------------------------------------------

    ; --- CORRECCIÓN VITAL: EXTRAER 'DE' REAL ---
    POP HL                      ; [1] Recuperamos pedidos en HL
    PUSH HL                     ; [1]
    PUSH DE                     ; [2] Guardamos leídos reales (DE) en la pila
    
    LD HL, (DMA_Address)
    CALL Z80_TruncateHL
    PUSH DE                     ; Salvamos reales
    LD DE, MSX_RAM
    ADD HL, DE
    POP DE                      
    
    ADD HL, DE                  ; HL = Destino relleno
    EX DE, HL                   ; DE = Destino relleno

    POP BC                      ; [2] BC = reales (para la resta)
    POP HL                      ; [1] HL = pedidos
    PUSH HL                     ; [1]
    PUSH BC                     ; [2] devolvemos reales a la pila

    OR A
    SBC HL, BC                  ; HL = a rellenar
    JR Z, .no_pad
    
    PUSH HL
    POP BC                      ; BC = a rellenar
    EX DE, HL                   ; HL = Destino relleno
    
    LD (HL), 1Ah
    DEC BC
    LD A, B
    OR C
    JR Z, .no_pad
    PUSH HL
    POP DE
    INC DE
    LDIR
.no_pad:
    
    POP DE                      ; [2] DE = reales
    PUSH DE                     ; [2]
    
    LD HL, (RB_RecSize)
    EX DE, HL                   
    CALL Div16_HL_DE            
    
    LD A, B
    OR C
    JR Z, .no_partial
    INC HL                      
.no_partial:
    
    LD (CPU_HL), HL             

    PUSH IX
    POP HL
    LD DE, 33
    ADD HL, DE
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE

    LD E, (HL)
    INC HL
    LD D, (HL)
    INC HL
    LD C, (HL)

    LD A, (CPU_HL+0)              
    ADD A, E
    LD E, A
    LD A, (CPU_HL+1)            
    ADC A, D
    LD D, A
    JR NC, .no_carry_rr
    INC C
.no_carry_rr:
    LD (HL), C
    DEC HL
    LD (HL), D
    DEC HL
    LD (HL), E

    POP DE                      ; [2] DE = reales
    POP HL                      ; [1] HL = pedidos
    POP BC                      ; [0]
    
    OR A
    SBC HL, DE                  
    JR NZ, .partial_or_eof
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.partial_or_eof:
    LD A, 01h                   
    LD (CPU_AF+1), A
    JP .bdos_return

.read_blk_err:
    POP HL                      
    LD HL, 0
    LD (CPU_HL), HL             
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_0A:
    CALL Z80_GetDE
    PUSH HL
    POP IX
    
    PUSH IX 
    POP HL
    CALL MSXMemory_ReadByte
    LD B, A
    OR A
    JP Z, .bdos_return
    
    LD C, 0
    
.loop_0A:
    CALL System_WaitKey
    
    CP 0Dh 
    JR Z, .done_0A
    CP 08h 
    JR Z, .bs_0A
    CP 7Fh 
    JR Z, .bs_0A
    
    PUSH AF
    LD A, C
    CP B 
    JR Z, .ignore_0A
    
    PUSH IX 
    POP HL
    INC HL 
    INC HL
    LD E, C
    LD D, 0
    ADD HL, DE
    
    POP AF
    PUSH AF
    CALL MSXMemory_WriteByte
    INC C
    
    POP AF
    RST.L 10h
    JR .loop_0A
    
.ignore_0A:
    POP AF
    JR .loop_0A
    
.bs_0A:
    LD A, C
    OR A
    JR Z, .loop_0A
    DEC C
    
    LD A, 08h 
    RST.L 10h
    LD A, ' ' 
    RST.L 10h
    LD A, 08h 
    RST.L 10h
    JR .loop_0A

.done_0A:
    PUSH IX 
    POP HL
    INC HL
    LD A, C
    CALL MSXMemory_WriteByte    ; Guardamos la longitud de la cadena

    ; --- EL FIX DEL SIGLO: AÑADIR CR (0Dh) AL FINAL ---
    LD E, C                     ; E = longitud de la cadena tecleada
    LD D, 0
    INC HL                      ; HL apunta al inicio de los caracteres
    ADD HL, DE                  ; Avanzamos HL hasta justo después del último carácter
    LD A, 0Dh                   ; El terminador obligatorio (Carriage Return)
    CALL MSXMemory_WriteByte    ; ¡Boom! Basura residual eliminada.
    ; --------------------------------------------------
    
    LD A, 0Dh 
    RST.L 10h
    LD A, 0Ah 
    RST.L 10h
    JP .bdos_return

; ----------------------------------------------------------
; FECHA Y HORA MSX-DOS
; ----------------------------------------------------------

.bdos_2A:
    ; GET DATE
    ; Salida MSX-DOS:
    ;   A  = día de la semana (0=Domingo ... 6=Sábado)
    ;   HL = año
    ;   D  = mes
    ;   E  = día

    LD A, (MSX_DateWeekday)
    LD (CPU_AF+1), A

    LD HL, (MSX_DateYear)
    LD (CPU_HL), HL

    LD A, (MSX_DateMonth)
    LD D, A
    LD A, (MSX_DateDay)
    LD E, A
    LD (CPU_DE), DE

    JP .bdos_return
    
.bdos_2B:
    ; SET DATE
    ; Entrada MSX-DOS:
    ;   HL = año
    ;   D  = mes
    ;   E  = día

    CALL Z80_GetHL
    LD (MSX_DateYear), HL

    CALL Z80_GetDE
    LD A, H                     ; H = D (mes) tras Z80_GetDE
    LD (MSX_DateMonth), A

    LD A, L                     ; L = E (día) tras Z80_GetDE
    LD (MSX_DateDay), A

    ; De momento conservamos el día de semana.
    ; COMMAND.COM no nos lo proporciona en SET DATE.

    XOR A
    LD (CPU_AF+1), A

    JP .bdos_return


.bdos_2C:
    ; GET TIME
    ; MSX-DOS:
    ;   H = hora
    ;   L = minutos
    ;   D = segundos
    ;   E = centésimas

    LD HL, (MSX_TimeHM)
    LD (CPU_HL), HL

    LD A, (MSX_TimeSecond)
    LD D, A

    LD A, (MSX_TimeHundredth)
    LD E, A
    LD (CPU_DE), DE

    XOR A
    LD (CPU_AF+1), A

    JP .bdos_return


.bdos_2D:
    ; SET TIME
    ; Entrada MSX-DOS:
    ;   H = hora
    ;   L = minutos
    ;   D = segundos
    ;   E = centésimas

    CALL Z80_GetHL
    LD (MSX_TimeHM), HL

    CALL Z80_GetDE
    LD A, H                     ; H = D (segundos) tras Z80_GetDE
    LD (MSX_TimeSecond), A

    LD A, L                     ; L = E (centésimas) tras Z80_GetDE
    LD (MSX_TimeHundredth), A

    XOR A
    LD (CPU_AF+1), A

    JP .bdos_return

.bdos_5A:
    ; Llamada interna/extensión de MSX-DOS ($5A)
    ; Devolvemos $FF silenciosamente para que COMMAND.COM continúe limpio
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

.bdos_return:
    ; --- TRAZA DE SALIDA ---
    LD A, (CPU_AF+1)
    CALL Debug_BDOS_Exit
    ; -----------------------

    CALL Z80_GetSP 
    CALL MSXMemory_ReadWord 
    PUSH HL
    CALL Z80_GetSP 
    INC HL 
    INC HL 
    CALL Z80_SetSP
    POP HL 
    CALL Z80_SetPC
    
    POP IY
    POP IX
    POP HL 
    POP DE 
    POP BC 
    POP AF
    RET



DEL_MAX_MATCHES: EQU 32

.bdos_13:
    ; --- DELETE con soporte de comodines. Primero recopilamos TODOS
    ;     los nombres que coinciden (sin borrar nada todavía, para no
    ;     modificar el directorio mientras FatFs lo está recorriendo -
    ;     borrar a mitad de un findfirst/findnext corrompe el escaneo),
    ;     y solo al final, con la búsqueda ya cerrada, borramos uno a
    ;     uno lo recopilado. ---
    CALL Z80_GetDE
    LD (current_search_fcb), HL

    XOR A
    LD (del_names_count), A

    CALL MSX_FS_SearchFirst
    OR A
    JR NZ, .del_none

.del_collect_loop:
    LD A, (del_names_count)
    CP DEL_MAX_MATCHES
    JR NC, .del_collect_next     ; buffer lleno, ignoramos coincidencias de más

    CALL Store_Search_Result_Name

.del_collect_next:
    CALL MSX_FS_SearchNext
    OR A
    JR Z, .del_collect_loop

    ; --- búsqueda ya cerrada: ahora sí, borrar cada nombre recogido ---
    LD A, (del_names_count)
    OR A
    JR Z, .del_none

    XOR A
    LD (del_unlink_index), A
    LD (del_deleted_count), A

.del_unlink_loop:
    LD A, (del_unlink_index)
    LD HL, del_names_count
    CP (HL)
    JR NC, .del_unlink_done

    CALL Build_Path_From_Stored_Name

    LD HL, fat_filename
    LD A, 97h                    ; ffs_unlink
    RST.L 08h
    OR A
    JR NZ, .del_unlink_skip
    LD A, (del_deleted_count)
    INC A
    LD (del_deleted_count), A
.del_unlink_skip:

    LD A, (del_unlink_index)
    INC A
    LD (del_unlink_index), A
    JR .del_unlink_loop

.del_unlink_done:
    LD A, (del_deleted_count)
    OR A
    JR Z, .del_none
    XOR A
    LD (CPU_AF+1), A
    JP .bdos_return

.del_none:
    LD A, 0FFh
    LD (CPU_AF+1), A
    JP .bdos_return

; ------------------------------------------------------------
; Guarda el nombre real (fat_filinfo+9 o +22) del resultado de
; búsqueda actual en el siguiente slot de del_names_buffer (13
; bytes/entrada, ASCIIZ) e incrementa del_names_count.
; ------------------------------------------------------------
Store_Search_Result_Name:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD A, (del_names_count)
    LD B, A
    LD HL, 0
    OR A
    JR Z, .ssrn_have_offset
.ssrn_mul_loop:
    LD DE, 13
    ADD HL, DE
    DJNZ .ssrn_mul_loop
.ssrn_have_offset:
    LD DE, del_names_buffer
    ADD HL, DE
    EX DE, HL                    ; DE = destino en del_names_buffer

    LD HL, fat_filinfo + 9       ; preferimos el nombre largo si lo hay
    LD A, (HL)
    OR A
    JR NZ, .ssrn_got_name
    LD HL, fat_filinfo + 22      ; si no, el nombre corto 8.3
.ssrn_got_name:
    LD B, 12                     ; máximo 12 caracteres + terminador
.ssrn_copy:
    LD A, (HL)
    OR A
    JR Z, .ssrn_term
    LD (DE), A
    INC HL
    INC DE
    DJNZ .ssrn_copy
.ssrn_term:
    XOR A
    LD (DE), A

    LD A, (del_names_count)
    INC A
    LD (del_names_count), A

    POP HL
    POP DE
    POP BC
    POP AF
    RET

; ------------------------------------------------------------
; Construye fat_filename = <carpeta de la unidad>/<nombre guardado
; en del_names_buffer[del_unlink_index]> - para operar sobre un
; resultado ya recopilado, sin ninguna búsqueda activa en curso.
; ------------------------------------------------------------
Build_Path_From_Stored_Name:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD A, (del_unlink_index)
    LD B, A
    LD HL, 0
    OR A
    JR Z, .bpfsn_have_offset
.bpfsn_mul_loop:
    LD DE, 13
    ADD HL, DE
    DJNZ .bpfsn_mul_loop
.bpfsn_have_offset:
    LD DE, del_names_buffer
    ADD HL, DE
    PUSH HL                      ; puntero al nombre guardado

    LD HL, (current_search_fcb)
    CALL Z80_TruncateHL
    LD DE, MSX_RAM
    ADD HL, DE
    LD A, (HL)
    AND 7Fh
    OR A
    JR NZ, .bpfsn_got_drive
    LD A, (current_drive)
.bpfsn_got_drive:
    CP 2
    JR Z, .bpfsn_drive_b
    LD HL, str_path_a
    JR .bpfsn_copy_path
.bpfsn_drive_b:
    LD HL, str_path_b
.bpfsn_copy_path:
    LD DE, fat_filename
.bpfsn_cp_loop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    OR A
    JR NZ, .bpfsn_cp_loop
    DEC DE                       ; retroceder sobre el terminador nulo

    LD A, '/'
    LD (DE), A
    INC DE

    POP HL                       ; recuperar puntero al nombre guardado
.bpfsn_name_loop:
    LD A, (HL)
    LD (DE), A
    INC HL
    INC DE
    OR A
    JR NZ, .bpfsn_name_loop

    POP HL
    POP DE
    POP BC
    POP AF
    RET



; --- rutina de división sin signo, 16/16 bits ---
; Entrada: HL = dividendo, DE = divisor (se asume DE<>0; el record
; size de MSX-DOS es 1..65535, así que en la práctica nunca es 0)
; Salida:  HL = cociente, BC = resto
Div16_HL_DE:
    LD BC, 0
    LD A, 16
.dloop:
    SLA L
    RL H
    RL C
    RL B
    PUSH HL
    LD H, B
    LD L, C
    OR A
    SBC HL, DE
    JR C, .nosub
    LD B, H
    LD C, L
    POP HL
    SET 0, L
    JR .dnext
.nosub:
    POP HL
.dnext:
    DEC A
    JR NZ, .dloop
    RET

; ----------------------------------------------------------
; TABLA DE HANDLES DEL HOST (SISTEMA ANTI-CORRUPCIÓN DE FCB)
; ----------------------------------------------------------
HandleTable_Init:
    PUSH AF
    PUSH BC
    PUSH HL
    LD HL, handle_table
    LD BC, 24
    XOR A
.ht_init_loop:
    LD (HL), A
    INC HL
    DEC BC
    LD A, B
    OR C
    JR NZ, .ht_init_loop
    POP HL
    POP BC
    POP AF
    RET

HandleTable_Store:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    CALL HandleTable_Free

    LD HL, handle_table
    LD B, 8
.ht_store_loop:
    LD A, (HL)
    INC HL
    OR (HL)
    DEC HL
    JR Z, .ht_found_free
    
    INC HL
    INC HL
    INC HL
    DEC B
    JR NZ, .ht_store_loop
    JR .ht_store_done

.ht_found_free:
    LD (HL), E
    INC HL
    LD (HL), D
    INC HL
    LD (HL), C

.ht_store_done:
    POP HL
    POP DE
    POP BC
    POP AF
    RET

HandleTable_Find:
    PUSH AF
    PUSH DE
    PUSH HL
    
    LD HL, handle_table
    LD B, 8
.ht_find_loop:
    LD A, (HL)
    CP E
    JR NZ, .ht_find_next
    INC HL
    LD A, (HL)
    CP D
    DEC HL
    JR Z, .ht_find_hit

.ht_find_next:
    INC HL
    INC HL
    INC HL
    DEC B
    JR NZ, .ht_find_loop

    LD C, 0
    JR .ht_find_done

.ht_find_hit:
    INC HL
    INC HL
    LD C, (HL)

.ht_find_done:
    POP HL
    POP DE
    POP AF
    RET

HandleTable_Free:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD HL, handle_table
    LD B, 8
.ht_free_loop:
    LD A, (HL)
    CP E
    JR NZ, .ht_free_next
    INC HL
    LD A, (HL)
    CP D
    DEC HL
    JR Z, .ht_free_hit

.ht_free_next:
    INC HL
    INC HL
    INC HL
    DEC B
    JR NZ, .ht_free_loop
    JR .ht_free_done

.ht_free_hit:
    XOR A
    LD (HL), A
    INC HL
    LD (HL), A
    INC HL
    LD (HL), A

.ht_free_done:
    POP HL
    POP DE
    POP BC
    POP AF
    RET

; ----------------------------------------------------------
; CONVERTIDOR RIGUROSO (AHORA CON ENRUTADOR SANDBOX)
; ----------------------------------------------------------
FCB_To_FatFilename:
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    LD IY, fat_filename
    
    ; --- NUEVO ENRUTADOR DINÁMICO ---
    PUSH IX
    POP HL
    CALL MSXMemory_ReadByte     ; Leer Drive original del FCB (Offset 0)
    OR A
    JR NZ, .got_drv
    LD A, (current_drive)       ; Si el FCB dice 00h, usamos nuestra unidad actual
.got_drv:
    CP 2
    JR Z, .use_b
.use_a:
    LD HL, str_path_a           ; Cargar ruta de A:
    JR .copy_path
.use_b:
    LD HL, str_path_b           ; Cargar ruta de B:
    
.copy_path:
    LD A, (HL)
    OR A
    JR Z, .path_done
    CALL ToLower                ; Aseguramos minúsculas por si acaso
    LD (IY), A
    INC IY
    INC HL
    JR .copy_path
.path_done:
    LD A, '/'                   ; <-- Inyectamos la barra aquí
    LD (IY), A                  ; <-- 
    INC IY                      ; <--

    PUSH IX
    POP HL
    INC HL
    
    LD B, 8
.fn_name_loop:
    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .fn_name_space
    CALL ToLower                ; <-- A MINÚSCULAS
    LD (IY), A
    INC IY
.fn_name_space:
    INC HL
    DEC B
    JR NZ, .fn_name_loop

    PUSH IX
    POP HL
    LD DE, 9
    ADD HL, DE
    
    CALL MSXMemory_ReadByte
    AND 7Fh
    LD B, A
    INC HL
    CALL MSXMemory_ReadByte
    AND 7Fh
    OR B
    LD B, A
    INC HL
    CALL MSXMemory_ReadByte
    AND 7Fh
    OR B
    CP ' '
    JR Z, .fn_no_ext

    LD A, '.'
    LD (IY), A
    INC IY

    PUSH IX
    POP HL
    LD DE, 9
    ADD HL, DE
    LD B, 3
.fn_ext_loop:
    CALL MSXMemory_ReadByte
    AND 7Fh
    CP ' '
    JR Z, .fn_ext_space
    CALL ToLower                ; <-- A MINÚSCULAS
    LD (IY), A
    INC IY
.fn_ext_space:
    INC HL
    DEC B
    JR NZ, .fn_ext_loop

.fn_no_ext:
    XOR A
    LD (IY), A

    POP HL
    POP DE
    POP BC
    POP AF
    RET

ToLower:
    CP 'A'
    RET C
    CP 'Z'+1
    RET NC
    ADD A, 32
    RET


; ----------------------------------------------------------
; HELPERS DE MEMORIA VIRTUAL
; ----------------------------------------------------------
MSXMemory_WriteByte:
    PUSH BC 
    PUSH HL 
    CALL Z80_TruncateHL
    LD BC, MSX_RAM 
    ADD HL, BC 
    LD (HL), A
    POP HL 
    POP BC 
    RET

MSXMemory_ReadByte:
    PUSH BC 
    PUSH HL 
    CALL Z80_TruncateHL
    LD BC, MSX_RAM 
    ADD HL, BC 
    LD A, (HL)
    POP HL 
    POP BC 
    RET

MSXMemory_ReadWord:
    PUSH BC
    CALL MSXMemory_ReadByte 
    LD C, A
    INC HL 
    CALL MSXMemory_ReadByte 
    LD B, A
    DEC HL 
    LD HL, 0 
    LD L, C 
    LD H, B
    POP BC 
    RET

MSXMemory_WriteWord:
    PUSH AF
    LD A, E 
    CALL MSXMemory_WriteByte
    INC HL 
    LD A, D 
    CALL MSXMemory_WriteByte
    DEC HL
    POP AF 
    RET

Clear_Buffer:
    ; HL = buffer
    ; BC = tamaño
    XOR A
.clear_loop:
    LD (HL), A
    INC HL
    DEC BC
    LD A, B
    OR C
    JR NZ, .clear_loop
    RET

; ==========================================================
; MSX_Console_PutChar
;
; 0 = normal
; 1 = después de ESC
; 2 = después de ESC x
; 3 = después de ESC y
; ==========================================================

MSX_Console_PutChar:

    LD B, A

    LD A, (console_esc_state)

    CP 0
    JR Z, .console_normal

    CP 1
    JR Z, .console_after_esc

    CP 2
    JR Z, .console_after_x

    CP 3
    JR Z, .console_after_y

    XOR A
    LD (console_esc_state), A
    LD A, B
    RST.L 10h
    RET


; ----------------------------------------------------------
; Estado NORMAL
; ----------------------------------------------------------

.console_normal:

    LD A, B
    CP 1Bh
    JR Z, .console_start_esc

    RST.L 10h
    RET


; ----------------------------------------------------------
; Hemos recibido ESC
; ----------------------------------------------------------

.console_start_esc:

    LD A, 1
    LD (console_esc_state), A
    RET


; ----------------------------------------------------------
; Segundo byte de ESC
; ----------------------------------------------------------

.console_after_esc:

    LD A, B

    CP 'x'
    JR Z, .console_esc_x

    CP 'y'
    JR Z, .console_esc_y

    ; ESC A/B/C/D/H/J/K:
    ; por ahora consumimos el código.
    CP 'A'
    JR Z, .console_escape_A

    CP 'B'
    JR Z, .console_escape_done

    CP 'C'
    JR Z, .console_escape_done

    CP 'D'
    JR Z, .console_escape_done

    CP 'H'
    JR Z, .console_escape_done

    CP 'J'
    JR Z, .console_escape_done

    CP 'K'
    JR Z, .console_escape_done

    ; Secuencia desconocida: descartar ESC.
    XOR A
    LD (console_esc_state), A
    RET


.console_esc_x:
    LD A, 2
    LD (console_esc_state), A
    RET


.console_esc_y:
    LD A, 3
    LD (console_esc_state), A
    RET


; ----------------------------------------------------------
; ESC x <param>
; ----------------------------------------------------------

.console_after_x:

    XOR A
    LD (console_esc_state), A
    RET


; ----------------------------------------------------------
; ESC y <param>
; ----------------------------------------------------------

.console_after_y:

    XOR A
    LD (console_esc_state), A
    RET

.console_escape_A:
    XOR A
    LD (console_esc_state), A

    ; Agon VDP: VDU 11 = cursor arriba una línea
    LD A, 0Bh
    RST.L 10h

    RET

.console_escape_done:

    XOR A
    LD (console_esc_state), A
    RET

PrintString:
    LD A, (HL) 
    OR A 
    RET Z
    RST.L 10h 
    INC HL 
    JR PrintString

PrintHexByte:
    PUSH AF
    RRCA
    RRCA
    RRCA
    RRCA
    CALL PrintNibble
    POP AF
    CALL PrintNibble
    RET

PrintHexWord:
    PUSH AF
    LD A, H
    CALL PrintHexByte
    LD A, L
    CALL PrintHexByte
    POP AF
    RET

PrintNibble:
    AND 0Fh
    CP 10
    JR C, .ph_is_digit
    ADD A, 7
.ph_is_digit:
    ADD A, '0'
    PUSH BC
    RST.L 10h
    POP BC
    RET

System_WaitKey:
    LD A, (key_lookahead)
    OR A
    JR Z, .poll_physical
    
    PUSH BC
    LD B, A
    XOR A
    LD (key_lookahead), A
    LD A, B
    POP BC
    RET
    
.poll_physical:
    LD A, 00h
    RST.L 08h
    OR A
    JR Z, .poll_physical
    RET

; ----------------------------------------------------------
; SISTEMA DE DEPURACIÓN DE LLAMADAS BDOS (ATRAPA-TODO)
; ----------------------------------------------------------
Print_ExitTrap_If_Debug:
    ; Imprime el aviso de warm boot solo si la traza está activa -
    ; usado por .exit_to_mos, .bdos_62 y .bdos_00 (las tres rutas
    ; de terminación de programa que hacen warm boot).
    PUSH AF
    PUSH HL
    LD A, (Debug_Enabled)
    OR A
    JR Z, .skip_exittrap_dbg
    LD HL, msg_exit_trap
    CALL PrintString
.skip_exittrap_dbg:
    POP HL
    POP AF
    RET

Debug_BDOS_Enter:
    PUSH AF
    LD A, (Debug_Enabled)
    OR A
    JR NZ, .dbg_enter_go
    POP AF
    RET
.dbg_enter_go:
    POP AF
; Ignorar funciones de consola masivas para no saturar
    CP 01h
    RET Z
    CP 02h
    RET Z
    CP 0Bh
    RET Z

    ; Trazar CUALQUIER OTRA función BDOS solicitada
    PUSH AF
    LD HL, msg_dbg_start
    CALL PrintString
    POP AF
    CALL PrintHexByte           ; Imprime número de BDOS (ej. 27)
    
    LD HL, msg_dbg_fcb
    CALL PrintString            ; Imprime " FCB:$"
    
    CALL Z80_GetDE
    LD A, H
    CALL PrintHexByte
    LD A, L
    CALL PrintHexByte

    ; --- NUEVO: para 26h/27h (bloques aleatorios), mostrar también HL ---
    ; (HL = número de registros/bloques pedido por COMMAND.COM)
    CALL Z80_GetBC
    LD A, L
    CP 26h
    JR Z, .dbg_show_hl
    CP 27h
    JR NZ, .dbg_no_hl
.dbg_show_hl:
    LD HL, msg_dbg_hl
    CALL PrintString            ; Imprime " HL=$"
    CALL Z80_GetHL
    LD A, H
    CALL PrintHexByte
    LD A, L
    CALL PrintHexByte
.dbg_no_hl:

    ; --- NUEVO: para 02h/06h (carácter) y 09h (cadena), mostrar el contenido real ---
    CALL Z80_GetBC
    LD A, L
    CP 02h
    JR Z, .dbg_show_char
    CP 06h
    JR Z, .dbg_show_char
    CP 09h
    JR Z, .dbg_show_str
    JR .dbg_no_console

.dbg_show_char:
    LD HL, msg_dbg_char
    CALL PrintString             ; Imprime " CHAR=$"
    CALL Z80_GetDE                ; L = E (el carácter, por convención Z80_GetDE)
    LD A, L
    CALL PrintHexByte
    JR .dbg_no_console

.dbg_show_str:
    LD HL, msg_dbg_str
    CALL PrintString             ; Imprime " STR=["
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD BC, MSX_RAM
    ADD HL, BC
    LD B, 24
.dbg_str_loop:
    LD A, (HL)
    CP '$'
    JR Z, .dbg_str_done
    OR A
    JR Z, .dbg_str_done
    CALL PrintHexByte
    LD A, ' '
    RST.L 10h
    INC HL
    DJNZ .dbg_str_loop
.dbg_str_done:
    LD A, ']'
    RST.L 10h
.dbg_no_console:

    LD HL, msg_dbg_arrow
    CALL PrintString            ; Imprime " -> A=$"
    RET

.dbg_fcb:
    PUSH AF
    LD HL, msg_dbg_start
    ;CALL PrintString
    POP AF
    ;CALL PrintHexByte           ; Imprime número de BDOS (ej. 0F)
    
    LD HL, msg_dbg_fcb
    ;CALL PrintString            ; Imprime " FCB:$"
    
    ; Imprimir dirección del FCB en Z80 (Registro DE)
    CALL Z80_GetDE
    LD A, H
    ;CALL PrintHexByte
    LD A, L
    ;CALL PrintHexByte

    LD HL, msg_dbg_file
    ;CALL PrintString            ; Imprime " File: "

    CALL Z80_GetDE
    PUSH HL
    POP IX
    CALL FCB_To_FatFilename
    LD HL, fat_filename
    ;CALL PrintString

    LD HL, msg_dbg_arrow
    ;CALL PrintString            ; Imprime " -> A=$"
    RET

.dbg_simple:
    PUSH AF
    LD HL, msg_dbg_start
    ;CALL PrintString
    POP AF
    ;CALL PrintHexByte
    LD HL, msg_dbg_arrow
    ;CALL PrintString
    RET

Debug_BDOS_Exit:
    PUSH AF
    LD A, (Debug_Enabled)
    OR A
    JR NZ, .dbg_exit_go
    POP AF
    RET
.dbg_exit_go:
    POP AF
    
    PUSH AF
    PUSH BC
    PUSH DE
    PUSH HL

    ; Comprobar si la última llamada BDOS era de disco
    CALL Z80_GetBC
    LD A, L
    CP 0Fh
    JR Z, .dbg_exit_do
    CP 0Ah                      ; <-- NUEVO: BUFIN
    JR Z, .dbg_exit_do
    CP 10h
    JR Z, .dbg_exit_do
    CP 11h
    JR Z, .dbg_exit_do
    CP 12h
    JR Z, .dbg_exit_do
    CP 13h
    JR Z, .dbg_exit_do
    CP 14h
    JR Z, .dbg_exit_do
    CP 15h
    JR Z, .dbg_exit_do
    CP 16h
    JR Z, .dbg_exit_do
    CP 17h                      ; <-- NUEVO: RENAME
    JR Z, .dbg_exit_do
    CP 1Ah                      ; <-- NUEVO
    JR Z, .dbg_exit_do
    CP 1Bh                      ; <-- NUEVO
    JR Z, .dbg_exit_do
    CP 26h                      ; <-- NUEVO
    JR Z, .dbg_exit_do
    CP 27h                      ; <-- NUEVO
    JR Z, .dbg_exit_do
    CP 2Ah                      ; <-- TIME/DATE
    JR Z, .dbg_exit_do
    CP 2Bh
    JR Z, .dbg_exit_do
    CP 2Ch                      ; <-- TIME/DATE
    JR Z, .dbg_exit_do
    CP 2Dh
    JR Z, .dbg_exit_do
  
    POP HL
    POP DE
    POP BC
    POP AF
    RET                         ; Si no es disco, salir sin imprimir nada

.dbg_exit_do:
    LD A, (CPU_AF+1)
    CALL PrintHexByte
    LD HL, msg_dbg_end
    CALL PrintString

    ; --- NUEVO: volcado de MSX_RAM+$0080..$008F tras SET DATE (2Bh) ---
    ; (buffer de entrada de consola: para ver qué deja ahí COMMAND.COM
    ;  justo antes de que su propia rutina $1269 decida si sigue con la hora)
    CALL Z80_GetBC
    LD A, L
    CP 2Bh
    JR NZ, .dbg_no_dump80

    LD HL, msg_dbg_dump80
    CALL PrintString
    LD HL, MSX_RAM + 0080h
    LD B, 16
.dbg_dump80_loop:
    LD A, (HL)
    CALL PrintHexByte
    LD A, ' '
    RST.L 10h
    INC HL
    DJNZ .dbg_dump80_loop
    LD HL, msg_dbg_nl
    CALL PrintString
.dbg_no_dump80:

    ; --- NUEVO: BUFIN (0Ah) real - DE real, max_len de entrada y bytes finales ---
    CALL Z80_GetBC
    LD A, L
    CP 0Ah
    JR NZ, .dbg_no_dump0A

    LD HL, msg_dbg_bufin
    CALL PrintString
    CALL Z80_GetDE
    LD A, H
    CALL PrintHexByte
    LD A, L
    CALL PrintHexByte
    LD HL, msg_dbg_end
    CALL PrintString

    LD HL, msg_dbg_bytes
    CALL PrintString
    CALL Z80_GetDE
    CALL Z80_TruncateHL
    LD BC, MSX_RAM
    ADD HL, BC
    LD B, 16
.dbg_dump0A_loop:
    LD A, (HL)
    CALL PrintHexByte
    LD A, ' '
    RST.L 10h
    INC HL
    DJNZ .dbg_dump0A_loop
    LD HL, msg_dbg_nl
    CALL PrintString
.dbg_no_dump0A:

    POP HL
    POP DE
    POP BC
    POP AF
    RET

; ----------------------------------------------------------
; INCLUSIÓN DEL MOTOR Z80
; ----------------------------------------------------------
    include "z80_cpu.asm"

; ==========================================================
; ZONA DE DATOS: VARIABLES INICIALIZADAS Y TEXTOS
; ==========================================================
; --- DEFINICIONES DE FATFS (Sustituir con mos_api.inc en el futuro) ---
msg_banner:         DB "MSX-DOS Virtual Environment v0.1", 10, 13, 0
msg_usage:          DB 10, 13, "Uso: msxdos.bin <programa.com> [argumentos...]", 10, 13, 0
msg_fail_load:      DB " -> Error FAT (No encontrado).", 10, 13, 0
msg_pass:           DB 10, 13, "Ejecucion Z80 finalizada.", 10, 13, 0
msg_unhandled_bdos: DB 10, 13, "[BDOS NO IMPLEMENTADO: $", 0
msg_crlf:           DB "]", 10, 13, 0
msg_dbg_start: DB 10, 13, "[DBG BDOS $", 0
msg_dbg_fcb:   DB " FCB:$", 0
msg_dbg_file:  DB " File: ", 0
msg_dbg_arrow: DB " -> A=$", 0
msg_dbg_hl:    DB " HL=$", 0
msg_dbg_char:  DB " CHAR=$", 0
msg_dbg_str:   DB " STR=[", 0
msg_dbg_dump80: DB 10, 13, "[DBG MEM $0080: ", 0
msg_dbg_delfcb: DB 10, 13, "[DBG DEL FCB: ", 0
msg_dbg_bufin:  DB 10, 13, "[DBG BUFIN DE=$", 0
msg_dbg_bytes:  DB "[DBG BUFIN BYTES: ", 0
msg_dbg_rrnum:  DB 10, 13, "[DBG RANDOM RECORD (27h)=$", 0
msg_dbg_gate:   DB 10, 13, "[DBG GATE A=$", 0
msg_dbg_path:  DB 10, 13, "[DBG OPEN-PATH: ", 0
msg_dbg_nl:    DB "]", 10, 13, 0
msg_dbg_end:   DB "]", 10, 13, 0
msg_bios_trap: DB 10, 13, "[TRAMPA] Intento de ejecucion BIOS en PC: $00", 0
msg_halt_pc: DB 13, 10, "[HALT PC=$", 0
msg_rst30: DB 10, 13, "[DBG BIOS] Bypass de llamada RST 30h destino: $", 0
msg_dbg_batch: DB 10, 13, "[DUMP] FCB $EF2F: ", 0
msg_dbg_vars:  DB 10, 13, "[DUMP] VARS (19,1A,3D,50,52): ", 0

msg_exit_trap:  DB 13, 10, "[MSX-DOS: programa terminado, recargando COMMAND.COM]", 13, 10, 0
msg_bdos0_trap: DB 13, 10, ">>> TRAP: Llamada a BDOS 00h (Warm Boot) <<<", 0
msg_fatal_exit: DB 13, 10, "[FATAL] Salida limpia al RET principal. Fin de la ejecucion.", 0

msg_search_path: DB 13, 10, "[SEARCH PATH] ", 0
msg_search_fcb: DB 13, 10, "[SEARCH FCB] ", 0
msg_mos94:      DB "[MOS $94] result=$", 0

msg_dbg_rename_src:    DB 13,10,"[REN SRC] ",0

msg_dbg_rename_dst:    DB " -> ",0

msg_msxdos_banner: DB "MSX-DOS version 1.00", 10, 13, "Copyright 1984 by Microsoft", 10, 13, 10, 13, 0

; --- ESTÉTICA MSX ---
msg_colors:     DB 17, 15, 17, 132, 12, 0   ; Texto Blanco (15), Fondo Azul (4+128), CLS (12)

; --- VARIABLES DEL ENTORNO SANDBOX ---
current_drive:  DB 1                        ; 1 = A:, 2 = B: (Empieza en A:)
str_path_a:     DB "/msxdos/a", 0          ; Ruta física de A: en la SD
str_path_b:     DB "/msxdos/b", 0          ; Ruta física de B: en la SD
str_star:       DB "*", 0
search_active:  DB 0

; --- GESTIÓN DE SALIDA (Comando BASIC) ---
msg_exit_mos:   DB 10, 13, "Saliendo a Agon MOS... (para BASIC ejecutia bbcbasic)", 10, 13, 0

; --- DPB (Disk Parameter Block) MSX-DOS (21 bytes) ---
dpb_a:
    DB 00h, 0F9h                ; DRIVE = A:, MEDIA = 2DD/720K
    DW 0200h                    ; SECSIZ = 512
    DB 0Fh, 04h, 01h, 02h       ; DIRMSK, DIRSHFT, CLUSMSK, CLUSSHFT
    DW 0001h                    ; FIRFAT = sector 1
    DB 02h, 70h                 ; FATCNT = 2, MAXENT = 112
    DW 000Eh                    ; FIRREC = sector 14
    DW 02CAh                    ; MAXCLUS = 714
    DB 03h                      ; FATSIZ = 3
    DW 0007h                    ; FIRDIR = sector 7
    DW 0000h                    ; FATPTR (Placeholder)

dpb_b:
    DB 01h, 0F9h                ; DRIVE = B:, MEDIA = 2DD/720K
    DW 0200h                    ; SECSIZ = 512
    DB 0Fh, 04h, 01h, 02h       ; DIRMSK, DIRSHFT, CLUSMSK, CLUSSHFT
    DW 0001h                    ; FIRFAT = sector 1
    DB 02h, 70h                 ; FATCNT = 2, MAXENT = 112
    DW 000Eh                    ; FIRREC = sector 14
    DW 02CAh                    ; MAXCLUS = 714
    DB 03h                      ; FATSIZ = 3
    DW 0007h                    ; FIRDIR = sector 7
    DW 0000h                    ; FATPTR (Placeholder)

; ==========================================================
; ZONA BSS: ESPACIO NO INICIALIZADO (DEBE SER EL FINAL)
; ==========================================================
CPU_AF:         DS 3
CPU_BC:         DS 3
CPU_DE:         DS 3
CPU_HL:         DS 3
CPU_IX:         DS 3
CPU_IY:         DS 3
CPU_AF_ALT:     DS 3
CPU_BC_ALT:     DS 3
CPU_DE_ALT:     DS 3
CPU_HL_ALT:     DS 3
CPU_PC:         DS 3
CPU_SP:         DS 3
CPU_I:          DS 1
CPU_R:          DS 1
CPU_IFF1:       DS 1
CPU_IFF2:       DS 1
CPU_IM:         DS 1
CPU_HALT:       DS 1
CPU_TStates:    DS 3

filename_buffer: DS 256
MSX_RAM:         DS 65536
key_lookahead:  DS 1
del_names_count: DS 1
del_unlink_index: DS 1
del_deleted_count: DS 1
del_names_buffer: DS 32*13
RR_Handle:      DS 1
RR_BytesRead:   DS 2

; ------------------------------------------------------------
; Interruptor único de toda la mensajería de depuración de esta
; sesión (traza BDOS, OPEN-PATH, REN SRC/DST, BDOS no implementado,
; aviso de warm boot...). 0 = apagado (por defecto). Cambia este
; valor a 1 para reactivar toda la traza de golpe, sin tener que
; tocar cada punto por separado.
; ------------------------------------------------------------
Debug_Enabled:  DB 0
DMA_Address:    DS 3
RB_RecSize:    DS 3
fat_filename:   DS  256
current_handle: DS 1

debug_last_conout: DS 1
console_esc_state: DS 1

; --- BUFFERS DE FATFS Y BÚSQUEDA ACTUALIZADOS ---
current_search_fcb: DS 3
fat_dir_obj:    DS 64
fat_filinfo:    DS 300

rename_src:    DS 128

handle_table:   DS 24           ; Tabla del Host: 8 slots * 3 bytes (AddrDE + Handle)

; ----------------------------------------------------------
; RELOJ VIRTUAL MSX-DOS
; ----------------------------------------------------------

MSX_DateYear:       DW 2026
MSX_DateMonth:      DB 8
MSX_DateDay:        DB 15
MSX_DateWeekday:    DB 6

MSX_TimeHM:         DW 0
MSX_TimeSecond:     DB 0
MSX_TimeHundredth:  DB 0
