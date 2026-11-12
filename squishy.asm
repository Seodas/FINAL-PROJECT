; SQUISHY TYCOON - standalone NASM source for 32-bit Linux / WSL.
; No include files are needed. This version is NOT a native Windows EXE.
; Assemble: nasm -f elf32 squishy.asm -o squishy.o
; Link:     gcc -m32 -no-pie squishy.o -o squishy
; Run:      ./squishy
; Ubuntu/WSL prerequisites: sudo apt install nasm gcc-multilib
;
; PRESENTATION: start at main, then explain squish, shop and file handling.
; All game code is assembly. GCC supplies the startup that calls main.
; Input/output and files use Linux int 0x80 system calls (no C functions).
; EAX = syscall number/result; EBX/ECX/EDX = first three syscall arguments.
; Our helpers preserve EBX/ESI/EDI/EBP; EAX/ECX/EDX may change on return.
; Dots name local branch labels. [name] accesses a variable in memory.
; dd declares 4-byte data, db bytes; resb reserves uninitialized storage.
; This 32-bit version caps lifetime earnings at 1 billion whole coins.
; Its save format is separate from the earlier Windows x64 version.

bits 32
global main
%define CAP 1000000000
%define SLOTS 10
%define PAYLOAD 200
%define SAVE_SIZE 204

; Procedure macros preserve the Linux i386 callee-saved registers.
; Sixteen local bytes follow EBX/ESI/EDI at EBP-16 through EBP-28.
%macro PROC 1
%1:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    sub esp, 16
%endmacro
%macro RETURN 0
    add esp, 16
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret
%endmacro
; Reuse text and number output without repeating argument setup.
%macro SAY 1
    mov eax, %1
    call print_z
%endmacro
%macro NUMBER 1
    mov eax, %1
    call print_number
%endmacro

section .text
; ENTRY AND MENU: GCC startup calls main; initialize a new game.
PROC main
    call reset_state
    SAY banner
.menu:
    call dashboard
    SAY menu_text
    call read_uint
    cmp edx, -1
    je .eof
    cmp edx, 1
    jne .bad
    cmp eax, 9
    ja .bad
    test eax, eax
    jz .exit
    cmp eax, 1
    je .single
    cmp eax, 2
    je .batch
    cmp eax, 3
    je .shop
    cmp eax, 4
    je .stats
    cmp eax, 5
    je .ledger
    cmp eax, 6
    je .save
    cmp eax, 7
    je .load
    cmp eax, 8
    je .help
    ; OPTION 9: confirm before erasing current progress.
    SAY reset_prompt
    call confirm
    test eax, eax
    jz .cancel
    call reset_state
    SAY reset_done
    jmp .menu
.single:
    ; OPTION 1: one squish uses the same transaction code as a burst.
    mov eax, 1
    call squish
    jmp .menu
.batch:
    ; OPTION 2: reject the entire action unless its quantity is 1-100.
    SAY batch_prompt
    call read_uint
    cmp edx, -1
    je .eof
    cmp edx, 1
    jne .batch_bad
    cmp eax, 1
    jb .batch_bad
    cmp eax, 100
    ja .batch_bad
    call squish
    jmp .menu
.batch_bad:
    SAY batch_error
    jmp .menu
.shop:
    ; OPTION 3: view the shop and buy only the next tier.
    call shop
    jmp .menu
.stats:
    ; OPTION 4: display totals without changing the game.
    call statistics
    jmp .menu
.ledger:
    ; OPTION 5: show the last ten successful transactions.
    call show_ledger
    jmp .menu
.save:
    ; OPTION 6: save and stay in the menu.
    call save_game
    jmp .menu
.load:
    ; OPTION 7: confirm before loading over current progress.
    SAY load_prompt
    call confirm
    test eax, eax
    jz .cancel
    call load_game
    jmp .menu
.help:
    ; OPTION 8: print stored instructions.
    SAY help_text
    jmp .menu
.cancel:
    SAY cancelled
    jmp .menu
.bad:
    SAY input_error
    jmp .menu
.exit:
    ; OPTION 0: a failed save keeps the menu open for another attempt.
    call save_game
    test eax, eax
    jz .menu
    SAY goodbye
    xor eax, eax
    RETURN
.eof:
    ; No input remains: save once and return 0 on success, 1 on failure.
    SAY eof_text
    call save_game
    xor eax, 1
    RETURN

; TEXT OUTPUT: EAX points to a zero-terminated string.
PROC print_z
    mov ecx, eax
    xor edx, edx
.length:
    cmp byte [ecx+edx], 0
    je .write
    inc edx
    jmp .length
.write:
    ; Linux write(1, pointer, length); retry interruptions and short writes.
    test edx, edx
    jz .done
    mov eax, 4
    mov ebx, 1
    int 0x80
    cmp eax, -4
    je .write
    test eax, eax
    jle .fatal
    add ecx, eax
    sub edx, eax
    jmp .write
.fatal:
    ; If output fails there is no usable console; exit with code 2.
    mov eax, 1
    mov ebx, 2
    int 0x80
.done:
    RETURN

; NUMBER OUTPUT: EAX contains an unsigned 32-bit value.
PROC print_number
    mov edi, number_buffer+15
    mov byte [edi], 0
    mov ebx, 10
.digit:
    ; Division produces a remainder 0-9; build decimal digits backward.
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .digit
    mov eax, edi
    call print_z
    RETURN

; BOUNDED INPUT: EAX=1 for a line, 0 if oversized, -1 for EOF/error.
PROC read_line
    xor esi, esi
    xor edi, edi
.read:
    ; Read one byte. Never let a long line overwrite another variable.
    mov eax, 3
    xor ebx, ebx
    mov ecx, input_byte
    mov edx, 1
    int 0x80
    cmp eax, -4
    je .read
    cmp eax, 1
    jne .eof
    mov al, [input_byte]
    cmp al, 10
    je .finish
    cmp esi, 127
    jae .long
    mov [input_buffer+esi], al
    inc esi
    jmp .read
.long:
    ; Drain excess characters to newline so they cannot become commands.
    mov edi, 1
    jmp .read
.eof:
    test esi, esi
    jnz .finish
    test edi, edi
    jnz .finish
    mov eax, -1
    RETURN
.finish:
    ; Strip a final CR if the input used Windows CRLF line endings.
    test esi, esi
    jz .terminate
    cmp byte [input_buffer+esi-1], 13
    jne .terminate
    dec esi
.terminate:
    mov [input_length], esi
    mov byte [input_buffer+esi], 0
    mov eax, 1
    sub eax, edi
    RETURN

; STRICT DECIMAL INPUT: EDX=status (1/0/-1); EAX=value if successful.
PROC read_uint
    call read_line
    mov edx, eax
    cmp eax, 1
    jne .done
    xor eax, eax
    xor esi, esi
.leading:
    cmp esi, [input_length]
    jae .bad
    mov cl, [input_buffer+esi]
    cmp cl, ' '
    je .skip
    cmp cl, 9
    jne .digit
.skip:
    inc esi
    jmp .leading
.digit:
    ; Check UINT32_MAX before value*10+digit to prevent wrapping.
    movzx ecx, byte [input_buffer+esi]
    sub ecx, '0'
    cmp ecx, 9
    ja .bad
    cmp eax, 429496729
    ja .bad
    jb .add
    cmp ecx, 5
    ja .bad
.add:
    imul eax, eax, 10
    add eax, ecx
    inc esi
    cmp esi, [input_length]
    jae .valid
    mov cl, [input_buffer+esi]
    cmp cl, ' '
    je .trailing
    cmp cl, 9
    je .trailing
    jmp .digit
.trailing:
    ; After the digits, accept whitespace only, never another token.
    inc esi
    cmp esi, [input_length]
    jae .valid
    mov cl, [input_buffer+esi]
    cmp cl, ' '
    je .trailing
    cmp cl, 9
    je .trailing
.bad:
    xor eax, eax
    xor edx, edx
    RETURN
.valid:
    mov edx, 1
.done:
    RETURN

; CONFIRMATION: only a single y/Y surrounded by whitespace means yes.
PROC confirm
    call read_line
    cmp eax, 1
    jne .no
    xor esi, esi
.leading:
    cmp esi, [input_length]
    jae .no
    mov al, [input_buffer+esi]
    cmp al, ' '
    je .skip
    cmp al, 9
    jne .letter
.skip:
    inc esi
    jmp .leading
.letter:
    or al, 32
    cmp al, 'y'
    jne .no
.tail:
    inc esi
    cmp esi, [input_length]
    jae .yes
    mov al, [input_buffer+esi]
    cmp al, ' '
    je .tail
    cmp al, 9
    je .tail
.no:
    xor eax, eax
    RETURN
.yes:
    mov eax, 1
    RETURN

; NEW GAME: reset all persisted fields, then restore file identifiers.
PROC reset_state
    mov edi, state
    mov ecx, SAVE_SIZE
    xor eax, eax
    cld
    rep stosb
    mov dword [magic], 0x32335153 ; little-endian bytes "SQ32"
    mov dword [version], 1
    RETURN

; DASHBOARD: show current wallet, squishy, rate and the next price.
PROC dashboard
    SAY separator
    SAY balance_label
    NUMBER [money]
    SAY current_label
    mov esi, [tier]
    mov eax, [names+esi*4]
    call print_z
    SAY rate_label
    NUMBER [rates+esi*4]
    SAY dashboard_end
    inc esi
    cmp esi, 6
    jae .max
    SAY next_label
    mov eax, [names+esi*4]
    call print_z
    SAY cost_label
    NUMBER [prices+esi*4]
    SAY newline
    RETURN
.max:
    SAY max_dashboard
    RETURN

; EARNING TRANSACTION: EAX=quantity already checked to be 1-100.
PROC squish
    mov esi, eax
    mov ecx, [tier]
    imul eax, [rates+ecx*4]
    mov edi, eax
    add eax, [earned]
    cmp eax, CAP
    ja .limit
    ; Commit only after validation; earnings cannot overflow at this cap.
    mov [earned], eax
    add [money], edi
    add [squishes], esi
    mov eax, edi
    mov edx, 1
    call record_transaction
    SAY squished_art
    SAY earned_label
    NUMBER edi
    SAY coins_label
    RETURN
.limit:
    SAY limit_text
    RETURN

; LEDGER INSERT: EAX=amount, EDX=1 earning or 2 purchase.
PROC record_transaction
    mov esi, [ledger_head]
    shl esi, 4                 ; 16 bytes per record
    inc dword [transactions]
    mov ecx, [transactions]
    mov [ledger+esi], ecx
    mov [ledger+esi+4], edx
    mov [ledger+esi+8], eax
    mov eax, [money]
    mov [ledger+esi+12], eax
    inc dword [ledger_head]
    cmp dword [ledger_head], SLOTS
    jb .count
    mov dword [ledger_head], 0
.count:
    ; Once full, overwrite the oldest record and retain exactly ten.
    cmp dword [ledger_count], SLOTS
    jae .done
    inc dword [ledger_count]
.done:
    RETURN

; SHOP: validate tier and balance, ask confirmation, then commit a debit.
PROC shop
    SAY shop_text
    mov esi, [tier]
    inc esi
    cmp esi, 6
    jae .max
    mov edi, [prices+esi*4]
    SAY offer_label
    mov eax, [names+esi*4]
    call print_z
    SAY cost_label
    NUMBER edi
    SAY newline
    cmp [money], edi
    jb .poor
    SAY buy_prompt
    call confirm
    test eax, eax
    jz .cancel
    ; Commit all purchase fields and record the resulting balance.
    sub [money], edi
    add [spent], edi
    mov [tier], esi
    mov eax, edi
    mov edx, 2
    call record_transaction
    SAY purchased
    cmp esi, 5
    jne .done
    SAY victory
.done:
    RETURN
.poor:
    ; Report only the shortage; no transaction takes place.
    SAY insufficient
    mov eax, edi
    sub eax, [money]
    call print_number
    SAY coins_label
    RETURN
.cancel:
    SAY cancelled
    RETURN
.max:
    SAY max_shop
    RETURN

; STATISTICS: read saved counters and convert the tier index to 1-6.
PROC statistics
    SAY stats_title
    SAY balance_label
    NUMBER [money]
    SAY squishes_label
    NUMBER [squishes]
    SAY lifetime_label
    NUMBER [earned]
    SAY spent_label
    NUMBER [spent]
    SAY tx_label
    NUMBER [transactions]
    SAY unlocked_label
    mov eax, [tier]
    inc eax
    call print_number
    SAY of_six
    RETURN

; LEDGER DISPLAY: iterate from oldest retained event to newest.
PROC show_ledger
    SAY ledger_title
    mov edi, [ledger_count]
    test edi, edi
    jz .empty
    mov esi, [ledger_head]
    sub esi, edi
    jns .row
    add esi, SLOTS
.row:
    ; Save the current record address across the text/number calls.
    mov ebx, esi
    shl ebx, 4
    add ebx, ledger
    SAY hash_label
    NUMBER [ebx]
    cmp dword [ebx+4], 1
    jne .buy
    SAY ledger_earn
    jmp .amount
.buy:
    SAY ledger_buy
.amount:
    NUMBER [ebx+8]
    SAY ledger_balance
    NUMBER [ebx+12]
    SAY newline
    inc esi
    cmp esi, SLOTS
    jb .next
    xor esi, esi
.next:
    dec edi
    jnz .row
    RETURN
.empty:
    SAY ledger_empty
    RETURN

; FNV-1a 32-bit checksum: EAX=payload pointer, return EAX=hash.
PROC checksum
    mov esi, eax
    mov ecx, PAYLOAD
    mov eax, 0x811c9dc5
.byte:
    movzx edx, byte [esi]
    xor eax, edx
    imul eax, eax, 0x01000193
    inc esi
    loop .byte
    RETURN

; FILE WRITE: temporary file -> complete write -> fsync -> close -> rename.
; Linux errors are negative syscall results. EINTR (-4) is retried.
PROC save_game
    mov eax, state
    call checksum
    mov [state_checksum], eax
.open:
    mov eax, 5                 ; open(temp, O_WRONLY|O_CREAT|O_TRUNC, 0600)
    mov ebx, temp_name
    mov ecx, 577
    mov edx, 384
    int 0x80
    cmp eax, -4
    je .open
    test eax, eax
    js .error
    mov edi, eax               ; keep descriptor across output/helper calls
    xor esi, esi               ; bytes successfully written
.write:
    mov eax, 4
    mov ebx, edi
    lea ecx, [state+esi]
    mov edx, SAVE_SIZE
    sub edx, esi
    int 0x80
    cmp eax, -4
    je .write
    test eax, eax
    jle .close_error
    add esi, eax
    cmp esi, SAVE_SIZE
    jb .write
.flush:
    ; Request a disk flush before publishing the temporary save.
    mov eax, 118               ; fsync(fd)
    mov ebx, edi
    int 0x80
    cmp eax, -4
    je .flush
    test eax, eax
    js .close_error
    mov eax, 6                 ; close(fd); do not retry close on Linux
    mov ebx, edi
    int 0x80
    test eax, eax
    js .error
.rename:
    ; rename replaces the old save only after a complete, closed write.
    mov eax, 38
    mov ebx, temp_name
    mov ecx, save_name
    int 0x80
    cmp eax, -4
    je .rename
    test eax, eax
    js .error
    SAY saved_text
    mov eax, 1
    RETURN
.close_error:
    mov eax, 6
    mov ebx, edi
    int 0x80
.error:
    SAY save_error
    xor eax, eax
    RETURN

; FILE READ: always stage data separately and validate before applying it.
PROC load_game
.open:
    mov eax, 5                 ; open(save, O_RDONLY, 0)
    mov ebx, save_name
    xor ecx, ecx
    xor edx, edx
    int 0x80
    cmp eax, -4
    je .open
    test eax, eax
    js .error
    mov edi, eax
    xor esi, esi
.read:
    ; Request one extra byte to detect an oversized save file.
    mov eax, 3
    mov ebx, edi
    lea ecx, [load_buffer+esi]
    mov edx, SAVE_SIZE+1
    sub edx, esi
    int 0x80
    cmp eax, -4
    je .read
    test eax, eax
    js .read_error
    jz .finish
    add esi, eax
    cmp esi, SAVE_SIZE+1
    jb .read
.finish:
    mov eax, 6
    mov ebx, edi
    int 0x80
    test eax, eax
    js .error
    cmp esi, SAVE_SIZE
    jne .corrupt
    call validate_save
    test eax, eax
    jz .corrupt
    ; Commit a checked save. The copy includes counters and all ring slots.
    mov esi, load_buffer
    mov edi, state
    mov ecx, SAVE_SIZE
    cld
    rep movsb
    SAY loaded_text
    mov eax, 1
    RETURN
.read_error:
    mov eax, 6
    mov ebx, edi
    int 0x80
.error:
    SAY load_error
    xor eax, eax
    RETURN
.corrupt:
    SAY corrupt_text
    xor eax, eax
    RETURN

; SAVE VALIDATION: check signature, version, checksum, ranges and accounting.
; All offsets here refer to 4-byte fields, not the old Windows save layout.
PROC validate_save
    mov eax, load_buffer
    call checksum
    cmp eax, [load_buffer+PAYLOAD]
    jne .bad
    mov ebx, load_buffer
    cmp dword [ebx], 0x32335153
    jne .bad
    cmp dword [ebx+4], 1
    jne .bad
    cmp dword [ebx+12], 6
    jae .bad
    cmp dword [ebx+20], CAP
    ja .bad
    cmp dword [ebx+16], CAP
    ja .bad
    mov eax, [ebx+20]
    cmp eax, [ebx+16]
    jb .bad                    ; each individual squish earns at least 1
    sub eax, [ebx+24]
    jc .bad
    cmp eax, [ebx+8]
    jne .bad                   ; wallet must equal earned minus spent
    mov eax, [ebx+16]
    mov ecx, 2000
    mul ecx                    ; full 64-bit EDX:EAX upper earnings bound
    test edx, edx
    jnz .spending              ; bound exceeds 32 bits, so CAP fits below it
    cmp [ebx+20], eax
    ja .bad
.spending:
    mov ecx, [ebx+12]
    mov eax, [cumulative_prices+ecx*4]
    cmp eax, [ebx+24]
    jne .bad
    ; One earning event represents 1-100 squishes; add one per paid tier.
    mov eax, [ebx+16]
    add eax, [ebx+12]
    cmp [ebx+28], eax
    ja .bad
    mov eax, [ebx+16]
    add eax, 99
    xor edx, edx
    mov ecx, 100
    div ecx
    add eax, [ebx+12]
    cmp [ebx+28], eax
    jb .bad
    ; Circular write position and retained count must match total events.
    mov eax, [ebx+28]
    xor edx, edx
    mov ecx, SLOTS
    div ecx
    cmp [ebx+36], edx
    jne .bad
    mov eax, [ebx+28]
    cmp eax, SLOTS
    jbe .count
    mov eax, SLOTS
.count:
    cmp [ebx+32], eax
    jne .bad
    mov [ebp-16], eax          ; events still to check
    mov esi, [ebx+36]
    sub esi, eax
    jns .first
    add esi, SLOTS
.first:
    mov edx, [ebx+28]
    sub edx, eax
    inc edx
    mov [ebp-20], edx          ; next expected sequence
    mov dword [ebp-28], 0     ; previous balance, zero for sequence 1
.record:
    cmp dword [ebp-16], 0
    je .good
    mov edi, esi
    shl edi, 4
    lea edi, [ebx+edi+40]
    mov edx, [ebp-20]
    cmp [edi], edx
    jne .bad
    cmp dword [edi+4], 1
    jb .bad
    cmp dword [edi+4], 2
    ja .bad
    cmp dword [edi+8], 0
    je .bad
    cmp dword [edi+8], CAP
    ja .bad
    cmp dword [edi+12], CAP
    ja .bad
    ; The oldest retained record can lack its predecessor after wrapping.
    cmp edx, 1
    je .chain
    mov eax, [ebx+32]
    cmp [ebp-16], eax
    je .remember
.chain:
    mov eax, [ebp-28]
    cmp dword [edi+4], 1
    jne .debit
    add eax, [edi+8]
    jc .bad
    jmp .compare
.debit:
    sub eax, [edi+8]
    jc .bad
.compare:
    cmp eax, [edi+12]
    jne .bad
.remember:
    mov eax, [edi+12]
    mov [ebp-28], eax
    inc dword [ebp-20]
    inc esi
    cmp esi, SLOTS
    jb .next
    xor esi, esi
.next:
    dec dword [ebp-16]
    jmp .record
.good:
    ; If there are events, the last recorded balance must equal the wallet.
    cmp dword [ebx+32], 0
    je .ok
    mov eax, [ebp-28]
    cmp eax, [ebx+8]
    jne .bad
.ok:
    mov eax, 1
    RETURN
.bad:
    xor eax, eax
    RETURN

section .rodata
; DISPLAY DATA: zero-terminated strings; numeric tables drive the rules.
; These strings are filled below with the game's commented screen data.
name0 db 'Mochi Blob',0
name1 db 'Peach Puff',0
name2 db 'Panda Bun',0
name3 db 'Axolotl Cloud',0
name4 db 'Dragon Jelly',0
name5 db 'Cosmic Squishy',0
align 4
names dd name0,name1,name2,name3,name4,name5
rates dd 1,5,20,100,400,2000
prices dd 0,25,150,800,4000,20000
cumulative_prices dd 0,25,175,975,4975,24975
save_name db 'squishy32.sav',0
temp_name db 'squishy32.sav.tmp',0

section .bss
; RUNTIME BUFFERS: not persisted. Input is bounded and decimal output fits.
input_byte resb 1
input_buffer resb 128
input_length resd 1
number_buffer resb 16
alignb 4
; SAVED LAYOUT: 40-byte header/counters, 160-byte ring, 4-byte checksum.
state:
magic resd 1                   ; signature "SQ32"
version resd 1                 ; save format 1
money resd 1                   ; earned - spent
tier resd 1                    ; equipped tier index 0-5
squishes resd 1                ; individual squishes, including bursts
earned resd 1                  ; all credited coins before purchases
spent resd 1                   ; all upgrade debits
transactions resd 1            ; successful events, not individual squishes
ledger_count resd 1            ; active records 0-10
ledger_head resd 1             ; next write slot 0-9
ledger resb 160                ; 10 x {sequence, kind, amount, balance}
state_checksum resd 1
load_buffer resb SAVE_SIZE+1   ; separate staging area + oversized-file byte

; Tell the Linux linker this program does not require an executable stack.
section .note.GNU-stack noalloc noexec nowrite progbits

section .rodata
banner db 13,10,'  ================================================',13,10
       db '       S Q U I S H Y   T Y C O O N',13,10
       db '          tiny blobs. big dreams.',13,10
       db '  ================================================',13,10
       db '                .-~~~~-.',13,10
       db '               /  o  o  \',13,10
       db '              (    __    )',13,10
       db '               `--------`',13,10
       db '  Start with a free Mochi Blob. Squish. Earn. Upgrade!',13,10
       db '  Coins are fictional. Use 7 to load an existing save.',13,10,0

; DASHBOARD STRINGS: pieces printed around the wallet, current name, reward and next upgrade.
separator db 13,10,'  ------------------------------------------------',13,10,0
balance_label db '  Wallet: ',0
current_label db ' coins | Squishy: ',0
rate_label db 13,10,'  Reward: ',0
dashboard_end db ' coins per squish',13,10,0
next_label db '  Next: ',0
cost_label db ' | Price: ',0
max_dashboard db '  Collection complete! Keep squishing for a high score.',13,10,0

; MENU TEXT: labels here correspond to the option branches in entry.
menu_text db 13,10,'  [1] Squish once          [2] Squish burst (1-100)',13,10
          db '  [3] Shop / buy next      [4] Statistics',13,10
          db '  [5] Transaction ledger  [6] Save game',13,10
          db '  [7] Load game           [8] How to play',13,10
          db '  [9] New game            [0] Save and exit',13,10
          db '  Choose 0-9, then press Enter: ',0

; INPUT MESSAGES: explain rejected menu numbers and invalid burst quantities.
input_error db 13,10,'  Enter a whole menu number from 0 to 9.',13,10,0
batch_prompt db '  How many squishes? (1-100): ',0
batch_error db '  Burst cancelled. Enter a whole number from 1 to 100.',13,10,0

; SQUISH FEEDBACK: flattened ASCII face followed by the amount earned.
squished_art db 13,10,'        ______________',13,10
             db '       (  >  __  <    )  S Q U I S H !',13,10
             db '        `------------`',13,10,0
earned_label db '  Earned +',0
coins_label db ' coins.',13,10,0
limit_text db '  Lifetime coin limit reached (1,000,000,000).',13,10
           db '  This squish was cancelled; start a new game to play again.',13,10,0

; SHOP DISPLAY: this human-readable table mirrors the numeric prices/rates tables below.
shop_text db 13,10,'  SQUISHY SHOP - buy the next tier in order',13,10
          db '  Tier   Squishy              Price     Coins/squish',13,10
          db '   1     Mochi Blob            FREE            1',13,10
          db '   2     Peach Puff              25            5',13,10
          db '   3     Panda Bun              150           20',13,10
          db '   4     Axolotl Cloud          800          100',13,10
          db '   5     Dragon Jelly         4000          400',13,10
          db '   6     Cosmic Squishy      20000         2000',13,10,0

; PURCHASE MESSAGES: next offer, affordability, confirmation, completion and final-tier victory.
offer_label db 13,10,'  Your next squishy: ',0
insufficient db '  Not enough coins. You still need ',0
buy_prompt db '  Spend these coins and replace your squishy? [y/N]: ',0
purchased db '  PURCHASE COMPLETE! The new squishy is now equipped.',13,10,0
victory db 13,10,'  * * * COLLECTION COMPLETE - COSMIC SQUISHY UNLOCKED! * * *',13,10,0
max_shop db '  You already own the highest tier. No purchase was made.',13,10,0
cancelled db '  Cancelled. Your progress is unchanged.',13,10,0

; STATISTICS LABELS: captions used when printing the saved counters.
stats_title db 13,10,'  YOUR SQUISHY BUSINESS',13,10,0
squishes_label db 13,10,'  Total squishes: ',0
lifetime_label db 13,10,'  Lifetime coins earned: ',0
spent_label db 13,10,'  Coins spent on upgrades: ',0
tx_label db 13,10,'  Successful transactions: ',0
unlocked_label db 13,10,'  Tiers unlocked: ',0
of_six db '/6',13,10,0

; LEDGER LABELS: display sequence, transaction type, amount and resulting wallet balance.
ledger_title db 13,10,'  TRANSACTION LEDGER - last 10 events, oldest first',13,10,0
ledger_empty db '  No transactions yet. Squish to earn your first coin!',13,10,0
hash_label db '  #',0
ledger_earn db '  EARN +',0
ledger_buy db '  BUY  -',0
ledger_balance db '  | Balance: ',0

; RESET AND LOAD PROMPTS: both require confirmation because they can replace current progress.
reset_prompt db '  Reset all CURRENT progress? Saved file stays until you save. [y/N]: ',0
reset_done db '  New game started. Your free Mochi Blob is ready!',13,10,0
load_prompt db '  Replace CURRENT progress with the saved game? [y/N]: ',0

; FILE-HANDLING MESSAGES: report successful saves/loads and failures without silently discarding progress.
saved_text db '  Saved successfully to squishy32.sav.',13,10,0
loaded_text db '  Save loaded successfully.',13,10,0
save_error db '  SAVE FAILED. Check folder permissions/free space; try again.',13,10
           db '  Your in-memory progress and previous save are preserved.',13,10,0
load_error db '  Cannot open/read squishy32.sav. Save first or check the folder.',13,10
           db '  Your current progress is unchanged.',13,10,0
corrupt_text db '  Invalid or damaged save. Your current progress is unchanged.',13,10,0

; EXIT MESSAGES: normal goodbye and the automatic-save notice when input ends.
goodbye db '  See you next squish!',13,10,0
eof_text db 13,10,'  Input ended. Saving current progress before exit...',13,10,0

; HELP SCREEN: explains every option, saving behavior, tier rewards and the lifetime coin cap.
help_text db 13,10,'  HOW TO PLAY',13,10
          db '  1. Press 1 and Enter to squish once and earn coins.',13,10
          db '  2. Use 2 for a burst of 1-100 squishes at the current rate.',13,10
          db '  3. Use 3 to view the shop. Buy only the next tier with y.',13,10
          db '     Purchases deduct the price and immediately raise earnings.',13,10
          db '     The new squishy replaces the old one; rates do not stack.',13,10
          db '  4. Use 4 for totals, or 5 for your last 10 transactions.',13,10
          db '  5. Use 6 to save; 7 loads after confirmation.',13,10
          db '     Saves are stored in the current working folder.',13,10
          db '     Start uses a new game; load explicitly to resume.',13,10
          db '  6. Use 9 to reset after confirmation. Save to keep the reset.',13,10
          db '  7. Use 0 to save and exit. A failed save keeps the menu open.',13,10
          db '  Unlock Cosmic Squishy to complete your collection!',13,10
          db '  Lifetime earning cap: 1 billion fictional coins.',13,10
          db '  Close with 0: closing the window may lose unsaved progress.',13,10,0

; COMMON TEXT AND TIER NAMES: names are zero-terminated strings referenced by tier_names.
newline db 13,10,0

