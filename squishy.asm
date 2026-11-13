; SQUISHY TYCOON 

global main
%define CAP 1000000000
%define SLOTS 10
%define PAYLOAD 200
%define SAVE_SIZE 204


; MACROS
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
%macro SAY 1
    mov eax, %1
    call print_z
%endmacro
%macro NUMBER 1
    mov eax, %1
    call print_number
%endmacro

section .text
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
    SAY reset_prompt
    call confirm
    test eax, eax
    jz .cancel
    call reset_state
    SAY reset_done
    jmp .menu
.single:
    mov eax, 1
    call squish
    jmp .menu
.batch:
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
    call shop
    jmp .menu
.stats:
    call statistics
    jmp .menu
.ledger:
    call show_ledger
    jmp .menu
.save:
    call save_game
    jmp .menu
.load:
    SAY load_prompt
    call confirm
    test eax, eax
    jz .cancel
    call load_game
    jmp .menu
.help:
    SAY help_text
    jmp .menu
.cancel:
    SAY cancelled
    jmp .menu
.bad:
    SAY input_error
    jmp .menu
.exit:
    call save_game
    test eax, eax
    jz .menu
    SAY goodbye
    xor eax, eax
    RETURN
.eof:
    SAY eof_text
    call save_game
    xor eax, 1
    RETURN

PROC print_z
    mov ecx, eax
    xor edx, edx
.length:
    cmp byte [ecx+edx], 0
    je .write
    inc edx
    jmp .length
.write:
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
    mov eax, 1
    mov ebx, 2
    int 0x80
.done:
    RETURN

PROC print_number
    mov edi, number_buffer+15
    mov byte [edi], 0
    mov ebx, 10
.digit:
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

PROC read_line
    xor esi, esi
    xor edi, edi
.read:
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

PROC reset_state
    mov edi, state
    mov ecx, SAVE_SIZE
    xor eax, eax
    cld
    rep stosb
    mov dword [magic], 0x32335153 ; little-endian bytes "SQ32"
    mov dword [version], 1
    RETURN

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

PROC squish
    mov esi, eax
    mov ecx, [tier]
    imul eax, [rates+ecx*4]
    mov edi, eax
    add eax, [earned]
    cmp eax, CAP
    ja .limit
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
    cmp dword [ledger_count], SLOTS
    jae .done
    inc dword [ledger_count]
.done:
    RETURN

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

;FILE HANDLE - SAVE
PROC save_game
    mov eax, state
    call checksum
    mov [state_checksum], eax
.open:
    mov eax, 5                
    mov ebx, temp_name
    mov ecx, 577
    mov edx, 384
    int 0x80
    cmp eax, -4
    je .open
    test eax, eax
    js .error
    mov edi, eax              
    xor esi, esi               
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
    mov eax, 118              
    mov ebx, edi
    int 0x80
    cmp eax, -4
    je .flush
    test eax, eax
    js .close_error
    mov eax, 6                 
    mov ebx, edi
    int 0x80
    test eax, eax
    js .error
.rename:
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

.open:
    mov eax, 5              
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


;FILE HANDLING - LOAD
PROC load_game
.open:
    mov eax, 5
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
    jb .bad                    
    sub eax, [ebx+24]
    jc .bad
    cmp eax, [ebx+8]
    jne .bad                  
    mov eax, [ebx+16]
    mov ecx, 2000
    mul ecx                    
    test edx, edx
    jnz .spending              
    cmp [ebx+20], eax
    ja .bad
.spending:
    mov ecx, [ebx+12]
    mov eax, [cumulative_prices+ecx*4]
    cmp eax, [ebx+24]
    jne .bad
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
    mov [ebp-16], eax          
    mov esi, [ebx+36]
    sub esi, eax
    jns .first
    add esi, SLOTS
.first:
    mov edx, [ebx+28]
    sub edx, eax
    inc edx
    mov [ebp-20], edx          
    mov dword [ebp-28], 0     
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
input_byte resb 1
input_buffer resb 128
input_length resd 1
number_buffer resb 16
alignb 4
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

separator db 13,10,'  ------------------------------------------------',13,10,0
balance_label db '  Wallet: ',0
current_label db ' coins | Squishy: ',0
rate_label db 13,10,'  Reward: ',0
dashboard_end db ' coins per squish',13,10,0
next_label db '  Next: ',0
cost_label db ' | Price: ',0
max_dashboard db '  Collection complete! Keep squishing for a high score.',13,10,0

menu_text db 13,10,'  [1] Squish once          [2] Squish burst (1-100)',13,10
          db '  [3] Shop / buy next      [4] Statistics',13,10
          db '  [5] Transaction ledger  [6] Save game',13,10
          db '  [7] Load game           [8] How to play',13,10
          db '  [9] New game            [0] Save and exit',13,10
          db '  Choose 0-9, then press Enter: ',0

input_error db 13,10,'  Enter a whole menu number from 0 to 9.',13,10,0
batch_prompt db '  How many squishes? (1-100): ',0
batch_error db '  Burst cancelled. Enter a whole number from 1 to 100.',13,10,0

squished_art db 13,10,'        ______________',13,10
             db '       (  >  __  <    )  S Q U I S H !',13,10
             db '        `------------`',13,10,0
earned_label db '  Earned +',0
coins_label db ' coins.',13,10,0
limit_text db '  Lifetime coin limit reached (1,000,000,000).',13,10
           db '  This squish was cancelled; start a new game to play again.',13,10,0

shop_text db 13,10,'  SQUISHY SHOP - buy the next tier in order',13,10
          db '  Tier   Squishy              Price     Coins/squish',13,10
          db '   1     Mochi Blob            FREE            1',13,10
          db '   2     Peach Puff              25            5',13,10
          db '   3     Panda Bun              150           20',13,10
          db '   4     Axolotl Cloud          800          100',13,10
          db '   5     Dragon Jelly         4000          400',13,10
          db '   6     Cosmic Squishy      20000         2000',13,10,0

offer_label db 13,10,'  Your next squishy: ',0
insufficient db '  Not enough coins. You still need ',0
buy_prompt db '  Spend these coins and replace your squishy? [y/N]: ',0
purchased db '  PURCHASE COMPLETE! The new squishy is now equipped.',13,10,0
victory db 13,10,'  * * * COLLECTION COMPLETE - COSMIC SQUISHY UNLOCKED! * * *',13,10,0
max_shop db '  You already own the highest tier. No purchase was made.',13,10,0
cancelled db '  Cancelled. Your progress is unchanged.',13,10,0

stats_title db 13,10,'  YOUR SQUISHY BUSINESS',13,10,0
squishes_label db 13,10,'  Total squishes: ',0
lifetime_label db 13,10,'  Lifetime coins earned: ',0
spent_label db 13,10,'  Coins spent on upgrades: ',0
tx_label db 13,10,'  Successful transactions: ',0
unlocked_label db 13,10,'  Tiers unlocked: ',0
of_six db '/6',13,10,0

ledger_title db 13,10,'  TRANSACTION LEDGER - last 10 events, oldest first',13,10,0
ledger_empty db '  No transactions yet. Squish to earn your first coin!',13,10,0
hash_label db '  #',0
ledger_earn db '  EARN +',0
ledger_buy db '  BUY  -',0
ledger_balance db '  | Balance: ',0

reset_prompt db '  Reset all CURRENT progress? Saved file stays until you save. [y/N]: ',0
reset_done db '  New game started. Your free Mochi Blob is ready!',13,10,0
load_prompt db '  Replace CURRENT progress with the saved game? [y/N]: ',0

saved_text db '  Saved successfully to squishy32.sav.',13,10,0
loaded_text db '  Save loaded successfully.',13,10,0
save_error db '  SAVE FAILED. Check folder permissions/free space; try again.',13,10
           db '  Your in-memory progress and previous save are preserved.',13,10,0
load_error db '  Cannot open/read squishy32.sav. Save first or check the folder.',13,10
           db '  Your current progress is unchanged.',13,10,0
corrupt_text db '  Invalid or damaged save. Your current progress is unchanged.',13,10,0

goodbye db '  See you next squish!',13,10,0
eof_text db 13,10,'  Input ended. Saving current progress before exit...',13,10,0

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


