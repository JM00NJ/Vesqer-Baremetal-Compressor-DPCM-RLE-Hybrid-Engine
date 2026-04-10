; ===============================================================================================
;      ___      ___ _______   ________  ________  _______   ________     
;     |\  \    /  /|\  ___ \ |\   ____\|\   __  \|\  ___ \ |\   __  \    
;     \ \  \  /  / | \   __/|\ \  \___|\ \  \|\  \ \   __/|\ \  \|\  \   
;      \ \  \/  / / \ \  \_|/_\ \_____  \ \  \\\  \ \  \_|/_\ \   _  _\  
;       \ \    / /   \ \  \_|\ \|____|\  \ \  \\\  \ \  \_|\ \ \  \\  \| 
;        \ \__/ /     \ \_______\____\_\  \ \__\\ _\\ \_______\ \__\\ _\ 
;         \|__|/       \|_______|\_________\|__|\|__|\|_______|\|__|\|__|
;                               \|_________|                             
;
;      ____  ____  ________  ___    ____  __    ______
;     / __ \/ __ \/ ____/  |/  /   / __ \/ /   / ____/
;    / / / / /_/ / /   / /|_/ /   / /_/ / /   / __/
;   / /_/ / ____/ /___/ /  / /   / _, _/ /___/ /___
;  /_____/_/    \____/_/  /_/   /_/ |_/_____/_____/
;
;      __  ____  ______  ____  ________    ______   _   __   ______   ____   _   __   ______
;     / / / /\ \/ / __ )/ __ \/  _/ __ \  / ____/  / | / /  / ____/  /  _/  / | / /  / ____/
;    / /_/ /  \  / __  / /_/ // // / / / / __/    /  |/ /  / / __    / /   /  |/ /  / __/
;   / __  /   / / /_/ / _, _// // /_/ / / /___   / /|  /  / /_/ /  _/ /   / /|  /  / /___
;  /_/ /_/   /_/_____/_/ |_/___/_____/ /_____/  /_/ |_/   \____/  /___/  /_/ |_/  /_____/
;
; ===============================================================================================
; Project      : VESQER Baremetal Compressor
; Module       : Compressor (Standalone)
; Author       : JM00NJ - https://github.com/JM00NJ
; Architecture : x86_64 Linux (Pure Assembly / Zero-Dependency)
; -----------------------------------------------------------------------------------------------
; Features:
;   - Algorithm   : Custom Differential Pulse-Code Modulation (DPCM) + RLE
;   - Native I/O  : Dynamic file descriptor handling via sys_open, read, write, close
;   - Evasion     : Zero libc dependencies, no predictable magic bytes
;   - Limits      : 5MB Input Buffer / 10MB Output Buffer (Overflow protection)
; -----------------------------------------------------------------------------------------------
; License: MIT License
; -----------------------------------------------------------------------------------------------
; Build: nasm -f elf64 decompress.asm -o decompress.o && ld decompress.o -o decompress
; Run  : ./decompress
; ===============================================================================================

section .bss
    filename resb 256               ; Buffer for file path
    compressed_buffer resb 5242880  ; 5 MB (Buffer for raw compressed input)
    decompressed_text resb 10485760 ; 10 MB (Buffer for decompressed output)

section .data
    ; Hardcoded path for testing (simulating dynamic input from .bss)
    input_file db 'compressed_output.bin', 0

section .text
global _start

_start:
    ; ==========================================
    ; STEP 1: SETUP FILE PATH (.bss simulation)
    ; ==========================================
    lea rsi, [input_file]
    lea rdi, [filename]
    mov rcx, 22                     ; Length of 'compressed_output.bin' + 1
    rep movsb                       

    ; ==========================================
    ; STEP 2: OPEN FILE (SYS_OPEN)
    ; ==========================================
    mov rax, 2                      ; sys_open
    lea rdi, [filename]             
    xor rsi, rsi                    ; flags: O_RDONLY (0)
    xor rdx, rdx                    ; mode: 0
    syscall

    test rax, rax
    js _exit_error                  ; Exit if file open fails
    mov r12, rax                    ; Backup file descriptor

    ; ==========================================
    ; STEP 3: READ FILE (SYS_READ)
    ; ==========================================
    mov rax, 0                      ; sys_read
    mov rdi, r12                    
    lea rsi, [compressed_buffer]    
    mov rdx, 5242880                ; Max bytes to read (5 MB)
    syscall

    test rax, rax
    jle _exit_error                 ; Exit if empty or read error

    mov r13, rax                    ; Backup actual bytes read (sys_close overwrites rcx)

    ; ==========================================
    ; STEP 4: CLOSE FILE (SYS_CLOSE)
    ; ==========================================
    mov rax, 3                      ; sys_close
    mov rdi, r12
    syscall

    ; ==========================================
    ; STEP 5: SETUP DECOMPRESSION POINTERS
    ; ==========================================
    lea rsi, [compressed_buffer]    
    lea rdi, [decompressed_text]    
    mov rcx, r13                    ; Set loop counter to actual bytes read

    test rcx, rcx
    jz _end_program

    ; --- Read Initial Anchor ---
    mov bl, byte [rsi]      
    inc rsi
    mov byte [rdi], bl      
    inc rdi
    dec rcx                 

_decompress_loop:
    test rcx, rcx
    jz _print_and_exit      

    ; --- Read Count and Delta ---
    mov dl, byte [rsi]      
    inc rsi
    dec rcx

    test rcx, rcx
    jz _print_and_exit      

    mov al, byte [rsi]      
    inc rsi
    dec rcx

    ; --- Calculate and Write ---
    test dl, dl
    jz _decompress_loop     

_write_loop:
    add bl, al              ; Current byte + Delta (Handles negatives via Two's Complement)
    mov byte [rdi], bl      
    inc rdi                 
    dec dl                  
    jnz _write_loop         

    jmp _decompress_loop    

_print_and_exit:
    ; --- PRINT TO STDOUT ---
    mov rdx, rdi                    
    lea rsi, [decompressed_text]    
    sub rdx, rsi                    ; Calculate exact decompressed length

    mov rax, 1              ; sys_write
    mov rdi, 1              ; fd: stdout
    syscall

_end_program:
    mov rax, 60             ; sys_exit
    xor rdi, rdi
    syscall

_exit_error:
    mov rax, 60
    mov rdi, 1              ; Exit code 1
    syscall
