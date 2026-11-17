bits 64
default rel

MEM_CONTROLLER_RESERVED_BYTES equ 0x15
MEMORY_ACCESS_PARAMETER_SET   equ 0x1
PROCESS_ROW_SIZE              equ 0x20    ; 4 x 8-byte fields

section .text
global memory_controller_init
global new_process
global get_mem_val

memory_controller_init:
    mov     byte [0x0], MEM_CONTROLLER_RESERVED_BYTES
    mov     al, MEMORY_ACCESS_PARAMETER_SET
    cmp     al, 0x0
    je      .no_restrictions

    movzx   rcx, byte [0x0]
    mov     byte [rcx], al              ; store restriction param at 0x15
    ret

.no_restrictions:
    mov     rbx, 0x1
    ret

; Input:
;   rdi = Program ID
;   rsi = Requested Space (bytes)
; Output:
;   rax = Virtual to Physical Offset (0 if invalid)
new_process:
    test    rdi, rdi
    jz      .fail
    test    rsi, rsi
    jz      .fail

    movzx   r9, byte [0x0]              ; r9 = memory controller reserved space (0x15)
    xor     r10, r10                    ; r10 = cumulative previous requested space
    lea     r8, [r9 + 0x1]              ; r8 = start of process table (0x16)

.find_row:
    mov     rax, [r8 + 0x00]            ; To End of Entry
    test    rax, rax
    jz      .write_row

    mov     r9,  [r8 + 0x18]            ; previous Virtual to Physical Offset
    mov     r10, [r8 + 0x10]            ; previous Requested Space
    add     r8, rax                     ; advance to next row
    jmp     .find_row

.write_row:
    add     r9, r10                     ; Virtual to Physical Offset = prev offset + prev space

    mov     qword [r8 + 0x00], PROCESS_ROW_SIZE
    mov     [r8 + 0x08], rdi            ; Program ID
    mov     [r8 + 0x10], rsi            ; Requested Space
    mov     [r8 + 0x18], r9            ; Virtual to Physical Offset

    mov     rax, r9
    ret

.fail:
    xor     eax, eax
    ret

get_mem_val:
    ret