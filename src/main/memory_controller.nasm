bits 64
default rel

MEM_CONTROLLER_RESERVED_BYTES equ 0x15
MEMORY_ACCESS_PARAMETER_SET equ 0x1
PROCESS_ROW_SIZE equ 0x20    ; 4 x 8-byte fields

section .text
global memory_controller_init
global new_process
global get_mem_val

memory_controller_init:
    mov byte [0x0], MEM_CONTROLLER_RESERVED_BYTES
    mov al, MEMORY_ACCESS_PARAMETER_SET
    cmp al, 0x0
    je .no_restrictions

    movzx rcx, byte [0x0]
    mov byte [rcx], al              ; store restriction param at 0x15
    ret

.no_restrictions:
    mov rbx, 0x1
    ret

; Input:
;   rdi = Program ID
;   rsi = Requested Space (bytes)
; Output:
;   rax = Virtual to Physical Offset (0 if invalid)
new_process:
    test rdi, rdi
    jz .fail
    test rsi, rsi
    jz .fail

    movzx r9, byte [0x0]              ; r9 = memory controller reserved space (0x15)
    xor r10, r10                    ; r10 = cumulative previous requested space
    lea r8, [r9 + 0x1]              ; r8 = start of process table (0x16)

.find_row:
    mov rax, [r8 + 0x00]            ; To End of Entry
    test rax, rax
    jz .write_row

    mov r9,  [r8 + 0x18]            ; previous Virtual to Physical Offset
    mov r10, [r8 + 0x10]            ; previous Requested Space
    add r8, rax                     ; advance to next row
    jmp .find_row

.write_row:
    add r9, r10                     ; Virtual to Physical Offset = prev offset + prev space

    mov qword [r8 + 0x00], PROCESS_ROW_SIZE
    mov [r8 + 0x08], rdi            ; Program ID
    mov [r8 + 0x10], rsi            ; Requested Space
    mov [r8 + 0x18], r9            ; Virtual to Physical Offset

    mov rax, r9
    ret

.fail:
    xor eax, eax
    ret

get_mem_val:
    ; RAX holds argument 0, RBX holds argument 1
    ; Argument 0 is the virtual address to read from
    ; Argument 1 is the program ID of the process that is requesting the read
    mov r8, 0x0
    mov r9, byte [r8]
    ; R9 now holds the length of the memory controller reserved space byte length.
    add r8, r9
    add r8, 0x1
    ; R8 now points to the start of the process table.
    ; We can now pass on the search to the .until_program_id_match function.
    jmp .until_program_id_match

.until_program_id_match:
    ; RAX holds the virtual address to read from
    ; RBX holds the program ID of the process that is requesting the read
    ; R8 holds the current index of the process table-list
    mov r10, [r8] ; Read the size of the current process data row
    add r8, 0x1 ; Move to the process ID field
    cmp rbx, [r8] ; Compare the program ID with the current process ID
    je .program_id_match ; If they match, jump to the program ID match section
    add r8, r10 ; Move to the next process data row
    cmp r8, 0x0 ; Check if we have reached the end of the process table
    je .fail ; If we have reached the end, jump to the fail section
    add r8, 0x2 ; Move to the next process data row
    jmp .until_program_id_match ; Repeat the search for the next process data row

.program_id_match:
    ; RAX holds the virtual address to read from
    ; RBX holds the program ID of the process that is requesting the read (No longer needed)
    ; R8 holds the current index of the process table-list (pointing to the process memory size field)
    mov r9, [r8] ; Read the length of the requested space value in bytes
    mov r10, r8 ; Store current (starting) index of the process table-list in R10
    add r8, 0x1 ; Move to the next entry
    ; Now we need to loop through the requested space value entry to find the requested space value.
    ; First loop can needs to be done here.
    ; The rest can be done in the .until_requested_space_finish function.
    xor rcx, rcx ; Clear RCX
    mov rcx, [r8]
    mov r11, r8
    sub r11, r10
    cmp r11, r9
    jne .until_requested_space_finish
    ; If we reach here, it means we found the requested space value and can continue.
    jmp .requested_space_found

.until_requested_space_finish:
    inc r8 ; Move to the next entry
    shl rcx, 8 ; Shift RCX left by 8 bits to align with the next byte
    mov cl, [r8] ; Read the next byte of the requested space value
    mov r11, r8 ; Store the current index of the process table-list in R11
    sub r11, r10 ; Calculate the offset from the starting index
    cmp r11, r9 ; Compare the offset with the length of the requested space value
    jne .until_requested_space_finish ; If not equal, continue the loop
    ; Otherwise we break out of the loop and continue with the script.
    jmp .requested_space_found

.requested_space_found:
    ; Now we have the requested space value in RCX and can compare the requested virtual address with the requested virtual address.
    ; If the requested virtual address is at a higher integer than the allocated space, we return 0x100 to indicate an invalid read, as currently using non-volatile memory is not supported.
    cmp rcx, rax ; Compare the requested space value with the requested virtual address
    jg .invalid_read ; If the requested virtual address is greater, jump to the invalid read section
    ; Otherwise, we can continue with the read operation.
    inc r8 ; Move to the next entry
    ; This entry holds the byte length of the virtual to physical offset value in bytes.
    xor rcx, rcx ; Clear RCX
    mov r9, [r8] ; Read the byte length of the virtual to physical offset value
    inc r8 ; Move to the next entry
    mov r10, r8 ; Store the current index of the process table-list in R10
    mov rcx, [r8] ; Read the virtual to physical offset value
    cmp r9, 0x1 ; Check if the byte length is 1, meaning that we already have the value we need.
    jne .until_virtual_physical_offset_finish ; If not equal, continue the loop to read the full value
    ; If equal, we can continue with the read operaition.
    jmp .virtual_physical_offset_found

.until_virtual_physical_offset_finish:
    inc r8 ; Move to the next entry
    shl rcx, 8 ; Shift RCX left by 8 bits to align with the next byte
    mov cl, [r8] ; Read the next byte of the virtual to physical offset value
    mov r11, r8 ; Store the current index of the process table-list in R11
    sub r11, r10 ; Calculate the offset from the starting index
    cmp r11, r9 ; Compare the offset with the length of the virtual to physical offset value
    jne .until_virtual_physical_offset_finish ; If not equal, continue the loop
    ; Otherwise we break out of the loop and continue with the script.
    jmp .virtual_physical_offset_found

.virtual_physical_offset_found:
    ; We can now apply the virtual to physical offset value.
    sub rax, rcx ; Subtract the virtual to physical offset value from the requested virtual address
    mov r8, rax ; Store the resulting physical address in R8
    ; Now we can return the physical address in RAX.
    mov rax, [r8] ; Move the physical address to RAX for return
    xor rcx, rcx ; Clear RCX
    xor rdx, rdx ; Clear RDX
    xor rbx, rbx ; Clear RBX
    xor rsi, rsi ; Clear RSI
    xor rdi, rdi ; Clear RDI
    xor r8, r8 ; Clear R8
    xor r9, r9 ; Clear R9
    xor r10, r10 ; Clear R10
    xor r11, r11 ; Clear R11
    ret ; Return the physical address in RAX