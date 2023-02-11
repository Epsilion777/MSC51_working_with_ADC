M equ 18 ; вариант
G equ 12 ; группа

num_ind1       equ r5 ; смещение в массиве Char_Ind для левого индикатора
num_ind2       equ r6 ; смещение в массиве Char_Ind для правого индикатора
current_num_kb equ r7 ; номер нажатой клавиши
UART_COUNT     equ 4*G ; последние 4*G записи кольцевого буфера для выдачи по UART

; Адреса внешних устройств

ADDR_RAMCS equ 0F000h
ADDR_KBRCS equ 0E800h
SG1        equ 0D800h
SG2        equ 0B800h
ADDR_ADCCS equ 7800h

dseg at 30h

X5:          ds 2     ; цифровое преобразование с АЦП аналогового сигнала
err_number:  ds 1     ; номер ошибки
buffer_size: ds 1     ; накопление записей до 4*G=4*12=48 записи для выдачи через UART
countUART_tosend ds 1 ; оставшееся кол-во записей для выдачи по UART
current_adr_FIFO ds 2 ; указатель на текущий элемент кольцевого буфера
Q:           ds 1     ; десятичное представление введенного числа

cseg 

jmp initialization
org 03h			 
jmp KB_INT		; обработчик для прерывания от клавиатуры
org 0Bh
jmp Y1_INT		; обработчик для прерывания от таймера 0
org 1Bh
jmp Y3_INT		; обработчик для прерывания от таймера 1
org 23h
jmp UART_INT	; обработчик для прерывания от UART
org 02Bh
jmp INT_ADC_CS	; обработчик  для прерывания от таймера 2

org 60h

; символы для включения на индикации: 0,1,2,3,4,5,6,7,8,9,E соответственно
Char_Ind: db 01000000b, 01111001b, 00100100b, 00110000b, 00011001b, 00010010b, 00000010b, 01111000b, 00000000b, 00010000b, 00000110b

; комбинации для конвертации 8-и битного представления нажатой клавиши в нормальный вид
; комбинации соответствуют клавишам: 0,1,2,3,4,5,6,7,8,9,A,B,C,D,ВВОД, СБРОС соответственно
Char_KB: db 10111110b, 01110111b, 10110111b, 11100111b, 01111011b, 10111011b, 11011011b, 01111101b, 10111101b, 11011101b, 11100111b,
11101011b,  11101101b, 11101110b, 01111110b, 11011110b

; -------- Инициализация -------
initialization:
    clr EA                     ; запрет всех прерываний
    mov Q, #42
    mov X5, #0
    mov X5+1, #0
    mov current_num_kb, #0FFh  ; инициализация (символ не введен)
    mov err_number, #0
    mov buffer_size, #0        ; изначально размер 0 записей
    mov current_adr_FIFO, #0   ; первые 4 байта занимают указатели
    mov current_adr_FIFO+1, #4
    mov current_adr_UART, #0   ; вспомогательный указатель для итерации по кольцевому буферу для UART
    mov current_adr_UART+1, #4 
    call init_ram              ; запись указателей на начало и конец кольцевого буфера
    call init_kb               ; инициализация клавиатуры
    call reset_ind             ; инициализация регистров для семисегментного индикатора

    mov IE, #00111011b         ; разрешение прерываний от внешнего INT0, таймеров 0,1,2 от UART и SPI

    clr SM0                    ; Работа UART в режиме 2
    setb SM1                   ;

    orl PCON, #10000000b       ; Скорость передачи UART 1/32 (SMOD = 1)

    setb IT0                   ; прерывание по срезу от INT0


    mov a, SPCR                ;
    setb acc.4                 ; МК работает в режиме master для интерфейса SPI
    clr acc.6                  ; отключаем работу SPE, включать будем в обработчике прерывания 
    mov spcr, a                ; 

    clr SPR0
	clr SPR1			       ; Частота синхросигналов для SPI 3 МГц

    MOV RCAP2H,#0FFh	       ; прерывание от таймера 2 каждые 200 мкс 
	MOV RCAP2L,#037h	
    mov TMOD,#00010001b        ; установка 16-бит режима для таймеров 0 и 1
    mov a, #1
    mov WCON, a                ; включаем работу сторожевого таймера с периодом 16 мс 
	сlr T2CON.0			       ; функция таймера
	сlr T2CON.1                ; в режиме перезагрузки
    setb T2CON.2               ; запуск таймера 2
    setb PT1                   ; высокий приоритет прерывания для таймера 1
    setb IP.5                  ; высокий приоритет прерывания для таймера 2
    
    setb p3.4                  ; Y1 высокого уровня
    clr p3.5                   ; Y3 низкого уровня
    setb p3.0                  ; выключить красный светодиод
    setb p3.3                  ; выключить зеленый светодиод

    setb EA

jmp start

; ------- Инициализациы клавиатуры -------
; За управление столбцами клавиатуры отвечают линии порта P1.0-P1.3 МК
init_kb:
    mov a, #11110000b
    mov p1, a         ; подать на столбцы клавиатуры нули
ret

; ------- Инициализациы внешнего буфера указателями на хвост и голову -------
init_ram
    mov dpl, #0                
    mov dph, #11110000b       ; в dph маска для обращения ко внешнему ОЗУ 
    mov a, #0                 
    movx @dptr, a              
    inc dpl                    
    mov a, #4                  
    movx @dptr, a              
    inc dpl                    
    mov a, #high(503h)         
    movx @dptr, a
    inc dpl
    mov a, #low(503h)
    movx @dptr, a
ret

; ------- Начало основного цикла программы -------
start:
    setb WDTRST ; сбросить сторожевой таймер

    mov a, err_number
    jnz err

    mov a, current_num_kb    ; аккумулятор содержит значение кнопки

    cjne a, #0FFh, key_down  ; если кнопка не нажималась, то пропускаем действия, иначе переход на key_down
    jmp clear_final

key_down:
    subb a, #0Ah             ; проверка нажата цифра или сервисная клавиа
    jc num_0_9_key           ; если цифра, то переход на num_0_9_key
    mov a, current_num_kb
; Далее идет анализ, какая была нажата клавиша - сервисная, ввод или сброс

; Кнопка A
    cjne a, #0Ah, button_B
    call proc_A
    jmp clear_final     
; Кнопка B
button_B:
    cjne a, #0Bh, button_C
    call proc_B
    jmp clear_final  

; Кнопка C
button_C:
    cjne a, #0Ch, button_D
    call proc_C
    jmp clear_final

; Кнопка D
button_D:
    cjne a, #0Dh, button_IN
    jmp clear_final

; Кнопка Ввод
button_IN:
    cjne a, #0Eh, button_RESET
    call proc_IN
    jmp clear_final

; Кнопка Сброс
button_RESET:
    cjne a, #0Fh, clear_final
    call reset_ind
    jmp clear_final

num_0_9_key:
     mov a, num_ind2                ; num_ind2 правый сегмент индикатора, num_ind1 левый
     cjne a, #0FFh, write_to_ind1   ; пустой ли num_ind2
     mov a, current_num_kb
     mov num_ind2, a
     call print_ind                 ; вывод значения на индикатор
     jmp clear_final
write_to_ind1:
     mov num_ind1, a                ; перезаписать num_ind2 на num_ind1, а на место
     mov num_ind2, current_num_kb   ; num_ind2 записать текущую цифру
     call print_ind                 ; вывод значения на индикатор

err:
    mov num_ind1, #0Ah              ; на первую позицию кладем смещение 0Ah для Char_Ind для вывода символа E
    mov num_ind2, err_number        ; на вторую позицию кладем номер ошибки
    call print_ind
cicl_err:
    setb WDTRST                     ; сбросить сторожевой таймер
    mov a, current_num_kb
    cjne a, #0Fh,  cicl_err         ; проверка - нажали "сброс"?
    mov err_number, #0
    call reset_ind
clear_final:
    mov current_num_kb, #0FFh       ; значение ненажатой кнопки current_num_kb
jmp start

; ------- Прерывание INT0 от клавиатуры -------
KB_INT:

    clr EX0
    mov dptr, #ADDR_KBRCS
    movx a, @dptr     ; считывание значение нажатой строки
    mov r1, a         ; теперь в R1 в старшей тетраде хранится значение строки

    mov a, #11111110b
    mov p1, a         ; устанавливаем 0 на первм столбце клавиатуры
    mov r2, a         ; запоминаем в R2 в младшей части номер столбца
    movx a, @dptr     ; считываем состояние клавиатуры, если старшая тетрада 1111, то в певром столбце кнопка не нажималась, иначе нажата
    anl a, #11110000b
    cjne a, #11110000b, result_kb

    mov a, #11111101b
    mov p1, a         ; устанавливаем 0 на первм столбце клавиатуры
    mov r2, a         ; запоминаем в R2 в младшей части номер столбца
    movx a, @dptr     ; считываем состояние клавиатуры, если старшая тетрада 1111, то во втором столбце кнопка не нажималась, иначе нажата
    anl a, #11110000b
    cjne a, #11110000b, result_kb

    mov a, #11111011b
    mov p1, a         ; устанавливаем 0 на первм столбце клавиатуры
    mov r2, a         ; запоминаем в R2 в младшей части номер столбца
    movx a, @dptr     ; считываем состояние клавиатуры, если старшая тетрада 1111, то в третьем столбце кнопка не нажималась, иначе нажата
    anl a, #11110000b
    cjne a, #11110000b, result_kb

    mov a, #11110111b
    mov p1, a         ; устанавливаем 0 на первм столбце клавиатуры
    mov r2, a         ; запоминаем в R2 в младшей части номер столбца
    movx a, @dptr     ; считываем состояние клавиатуры, если старшая тетрада 1111, то в четвертом столбце кнопка не нажималась, иначе нажата
    anl a, #11110000b
    cjne a, #11110000b, result_kb
                              ; иначе произошла ошибка
    mov err_number, #1h       ; номер ошибки 1 - ошибка при чтении клавиатуры
    jmp exit_kb
    
result_kb:
    mov a, r1
    anl a, #11110000b
    mov a, r2
    anl a, #00001111b
    orl a, r1

    mov r1, a          ; в r1 лежит код нажатой клавиши в 8-битном представлении (старшая тетрада - строка, младшая - столбец)
                       ; далее перевод 8-битного предсталвения в понятный вид
    mov r0, 0          ; смещение в массиве Char_KB
    mov dptr, #Char_KB
cicl_findChar:
    clr a
    movc a, @a+dptr
    cjne a, r1, next_num   ; если совпало значение,
    mov current_num_kb, r0 ; то кладем в переменную значение кнопки 0-15
    jmp exit_kb
next_num:
    inc r0
    inc dpl
    cjne r0, #0Fb, cicl_findChar
exit_kb:
    call init_kb
    setb EX0

reti

; ------- Процедура вывода данных на индикацию -------
print_ind:

    mov a, num_ind1         ; кладем в аккумулятор смещение левого символа
    mov dptr, #Char_Ind     ; dptr настраиваем на массив индикатора
    movc a, @a+dptr         ; кладем в аккумулятор значение для вывода на индикатор

    mov dptr, #SG1          ; смещение для обращения к регистру DD7
    movx @dptr, a           ; записали в регистр

    mov a, num_ind2         ; кладем в аккумулятор смещение правого символа
    mov dptr, #Char_Ind     ; dptr настраиваем на массив индикатора
    movc a, @a+dptr         ; кладем в аккумулятор значение для вывода на индикатор

    mov dptr, #SG2          ; смещение для обращения к регистру DD10
    movx @dptr, a           ; записали в регистр

ret

; ------- Процедура отчистки индикатора -------
reset_ind:

    mov a, #0FFh
    mov dptr, #SG1          ; смещение для обращения к регистру DD8
    movx @dptr, a           ; записали в регистр

    mov dptr, #SG2          ; смещение для обращения к регистру DD11
    movx @dptr, a           ; записали в регистр

    mov num_ind1, #0FFh     ; сброс значений смещений
    mov num_ind2, #0FFh
    
ret

; ------- Процедура обрабоки нажатия клавиши "Ввод" -------
;(преобразования сигнала Xd в десятичную величину Q и выдача строба)
proc_IN:

    mov a, num_ind2            ; считали в аккумулятор правую цифру индикатора
    cjne a, #0FFh, go_to_solve ; проверка есть ли на правом индикаторе символ
    mov err_number, #2         ; номер ошибки 2 - ошибка при нажатии кнопки ввода, при пустом индикаторе
    jmp exit_input
go_to_solve:
    mov a, num_ind1
    cjne a, #FFh, go_mul
    mov num_ind1, #0h
go_mul:
    mov a, num_ind1            ; в аккумуляторе левый символ индикатора
    mov b, #0Ah
    mul ab
    add a, num_ind2            ; теперь в аккумуляторе десятичное представление введенного числа
    mov Q, a                   ; сохраняем новое значение в Q

    call reset_ind
    mov TH0, #high(-18000)     ; длительность 1 машинного цикла 1 мкс, значит
    mov TL0, #low(-18000)      ; таймер отработает 18мс (как и требуется по условию ТЗ)
    clr p3.4                   ; строб низкого уровня Y1
    setb TR0
exit_input:
ret

; ------- Обработка прерывания от таймера 0 -------
Y1_INT:

    cpl p3.4        ; инвертируем линию порта
    clr TR0
    clr TF0

reti

; ------- Обработка прерывания от таймера 2 -------
INT_ADC_CS:
    clr TF2
    clr p2.7                ; перевод АЦП в режим выдачи данных
    orl SPCR, #01000000b    ; разрешение работы SPI (SPE = 1)
    mov SPDR, a             ; кладем в SPDR любое значение
cicl1_adc:
    mov a, SPSR
    jnb acc.7, cicl1_adc    ; ожидание принятия данных (Когда SPIF = 1)
;   ! Чтение данных с АЦП в регистры r3 и r4 !
    mov r3, SPDR            ; В r3 старшая часть преобразованного сигнала
    anl SPSR, #01111111b    ; сброс SPIF в 0
    mov SPDR, a             ; кладем в SPDR любое значение
cicl2_adc:
    mov a, SPSR
    jnb acc.7, cicl2_adc    ; ожидание принятия данных (Когда SPIF = 1)
    mov r4, SPDR            ; В r4 младшая часть преобразованного сигнала  
    anl SPSR, #01111111b    ; сброс SPIF в 0
    ;mov dptr, #ADDR_ADCCS
    ;movx @dptr, a           ; перевод АЦП в режим преобразования сигнала
    setb p2.7               ; перевод АЦП в режим преобразования сигнала
    anl SPCR, #10111111b    ; запрет работы SPI (SPE = 0)
;   ! Данные в регистрах представляют следующий вид:
;   r3: D13, D12, D11, D10, D9, D8, D7, D6
;   r4: D5, D4, D3, D2, D1, D0, X, X
;   Поэтому сдвигаем данные в регистрах вправо на 2 разряда
    clr C       ;
    mov a, r3   ;
    rrc a       ;
    mov r3, a   ; сдвиг r3-r4 на 1 разряд вправо
    mov a, r4   ;
    rrc a       ;
    mov r4, a   ;

    clr C       ;
    mov a, r3   ;
    rrc a       ;
    mov r3, a   ; сдвиг r3-r4 на 1 разряд вправо
    mov a, r4   ;
    rrc a       ;
    mov r4, a   ;

    mov x5, r3  ; в переменную X5 кладем значение оцифрованного сигнала
    mov x5+1, r4

;   Вычисление значения |3Q+G-2M|
    call solve_task ; r0 содержит старшую часть результата |3Q+G-2M|, r1 младшую
    mov a, r3       ; в a кладем старшую часть X5
    clr c
    subb a, r0
    jc off_red_diode
;   Иначе проверяем младшую часть
    mov a, r4       ; в a кладем младшую часть X5
    clr c
    subb a, r1
    jc off_red_diode
;   Иначе включаем красный светодиод
    clr p3.0
    jmp skip_off_red
off_red_diode:
    setb p3.0       ; выключаем красный светодиоддиод
skip_off_red:
;   Вычисление значения управляющего воздействия: Y2=M+X5
    mov a, r4       ; в a кладем младшую часть X5
    add a, #M 
    mov r4, a
    mov a, r3       ; в a кладем старшую часть X5       
    addc a, #0
    mov r3, a       ; теперь в r4 старшая часть Y2, а в r3 младшая часть Y2
;   Сохранение этой величины во внешнем ОЗУ статического типа
    mov a, current_adr_FIFO             ;
    cjne a, #high(503h), good_event1    ; 
    mov a, current_adr_FIFO+1           ;
    cjne a, #low(503h), good_event1     ; проверка дошли ли до конца кольцевого буфера
;   Если дошли до конца
    mov a, #0                           ;
    mov current_adr_FIFO, a             ;
    mov a, #04h                         ; устанавливаем адрес начала кольцевого буфера
    mov current_adr_FIFO+1, a           ;
;   Отправка 2 байт Y2 во внешнее ОЗУ
good_event1:
    mov a, current_adr_FIFO
    orl a, #11110000b
    anl a, #11110111b                   ; порт p2 будет содержать комбинацию 1 1 1 1 0 A10 A9 A8
    mov dph, a                          ; в dph кладем A8-A10 и маска, которая активирует внешнее ОЗУ
    mov dpl, current_adr_FIFO+1         ; в dpl кладем A0-A7 для внешнего ОЗУ
    mov a, r3                           
    movx @dptr, a                       ; отправляем по адресу старший байт Y2
    
    mov a, current_adr_FIFO+1           ;
    add a, #1                           ;
    mov current_adr_FIFO+1, A           ;
    mov a, current_adr_FIFO             ; увеличиваем адрес на 1
    addc a, #0                          ;
    mov current_adr_FIFO, a             ;

    mov a, current_adr_FIFO
    orl a, #11110000b
    anl a, #11110111b                   ; порт p2 будет содержать комбинацию 1 1 1 1 0 A10 A9 A8

    mov dph, a                          ; в dph кладем A8-A10 и маска, которая активирует внешнее ОЗУ
    mov dpl, current_adr_FIFO+1         ; в dpl кладем A0-A7 для внешнего ОЗУ
    mov a, r4 
    movx @dptr, a                       ; отправляем по адресу младший байт Y2

    mov a, current_adr_FIFO+1           ;
    add a, #1                           ;
    mov current_adr_FIFO+1, A           ;
    mov a, current_adr_FIFO             ; увеличиваем адрес на 1
    addc a, #0                          ;
    mov current_adr_FIFO, a             ;

    mov a, buffer_size
    cjne a, #UART_COUNT, inc_buffer     ; проверяем накопилось ли 48 записей для выдачи по UART
    jmp end_adc

inc_buffer:
    inc a 
    mov buffer_size, a
end_adc:
reti

; ------- Процедура обрабоки нажатия клавиши "A" -------
proc_A:

    mov a, buffer_size
    cjne a, #UART_COUNT, err_size      ; если в кольцевом буфере не набралось 48 записей то выдать ошибку
    mov countUART_tosend, #96          ; 48 записей, 1 запись - 2 байта
    mov a, current_adr_FIFO
    mov current_adr_UART, a 
    mov a, current_adr_FIFO+1
    mov current_adr_UART+1, a          ; теперь в current_adr_UART хранится адрес текущего элемента кольцевго буфера

    setb TI                            ; инициируем прерывание для передачи данных
    jmp exit_A
err_size:
    mov err_number, #3, ; номер ошибки 3 - нехватка записей в буфере для выдачи через UART
exit_A:

ret

; ------- Обработка прерывания UART -------
UART_INT:
    clr TI

    mov a, countUART_tosend     ; остались ли байты для передачи
    jnz send_byte

    call reset_ind
    jmp end_uart

send_byte:
    mov a, #countUART_tosend ;
    mov b, #10               ;
    div ab                   ;
    mov num_ind2, b          ;  Выввод индикации прогресса (обратный отсчет)
    mov num_ind1, a          ;
    call print_ind           ;
    dec countUART_tosend

    mov a, current_adr_UART+1   ;
    clr C                       ;
    subb a, #1                  ;
    mov current_adr_UART+1, a   ; уменьшаем адрес на 1
    mov a, current_adr_UART     ; 
    subb a, #0                  ;
    mov current_adr_UART, a     ;

    jnz good_event                     ; если старшая часть адреса не 0

check:
    mov a, current_adr_UART+1
    cjne a, #03h, good_event           ; проверяем дошли ли до начала кольцевого буфера
    mov current_adr_UART+1, #low(503h) ; если дошли, то присваеваем текущему укзаателю адрес
    mov current_adr_UART, #high(503h)  ; конца кольцевого буфера
good_event:
    mov a, current_adr_UART
    orl a, #11110000b
    anl a, #11110111b                  ; накладываем на адрес маску для обращения к внешнему ОЗУ
                                       ; порт p2 будет содержать комбинацию 1 1 1 1 0 A10 A9 A8
    mov dph, a
    mov dpl current_adr_UART+1         ; настраиваем dptr на нужную ячейку
    movx a, @dptr
    mov sbuf, a                 
end_uart:
reti
; ------- Процедура обрабоки нажатия клавиши "B" -------
;(Включение/Выключение генератора периодического сигнала и индицирвать включенное состояние зеленым светодиодом)
;Ширина имплуьса = 12 мс, период 22+2*12=58 мс, тогда низкий уровень 58-12=46 мс
proc_B:

    mov TH1, #high(-12000)
    mov TL1, #low(-12000)

    mov a, PCON            ;
    setb acc.2             ; GF0: 1 - сейчас высокий уровень, 0 - низкий (Устанавливаем GF=1)
    mov PCON, a            ;
  
    setb p3.5              ; высокий уровень Y3 
    clr p3.3               ; зеленый светодиод включить
    setb TR1

ret

; ------- Обработка прерывания от таймера 1 -------
Y3_INT:
    mov a, PCON
    jb acc.2, high_level
    clr TF1
    mov TH1, #high(-12000)
    mov TL1, #low(-12000)
    setb p3.5              ; высокий уровень Y3 

    mov a, PCON            ;
    setb acc.2             ; GF0: 1 - сейчас высокий уровень, 0 - низкий (Устанавливаем GF=1)
    mov PCON, a            ;

    jmp end_int3

high_level:
    clr TF1
    mov TH1, #high(-46000)
    mov TL1, #low(-46000)
    clr p3.5               ; низкий уровень Y3 
    
    mov a, PCON            ;
    setb acc.2             ; GF0: 1 - сейчас высокий уровень, 0 - низкий (Устанавливаем GF=0)
    mov PCON, a            ;

end_int3:

reti

; ------- Процедура обрабоки нажатия клавиши "C" -------
proc_C:

    clr TF1
    clr p3.5               ; низкий уровень Y3
    cpl p3.3               ; зеленый светодиод выключить
    clr TR1

ret

; ------- Процедура вычисления значения |3*Q+G-2M| -------
;На выходе в r0 старшая часть результата, в r1 младшая часть результата 

solve_task:

    mov a, Q
    mov b, 3 
    mul ab
    mov r0, b    ; в r0 старшая часть результата 3*Q
    mov r1, a    ; в r1 младшая часть результата 3*Q
    clr C
    add a, #G
    mov r1, a    ; в r1 младшая часть результата 3*Q+G
    mov a, r0
    addc a, #0
    mov r0, a    ; в r0 старшая часть результата 3*Q+G
    clr c
    mov a, r1
    subb a, #M
    mov r1, a    ; в r1 младшая часть результата 3*Q+G-M
    mov a, r0
    subb a, #0
    mov r0, a    ; в r0 старшая часть результата 3*Q+G-M
    clr c
    mov a, r1
    subb a, #M
    mov r1, a    ; в r1 младшая часть результата 3*Q+G-2M
    mov a, r0
    subb a, #0
    mov r0, a    ; в r0 старшая часть результата 3*Q+G-2M
    
    jb acc.7, negative
    jmp exit_solve_task

negative:
    mov a, r0    ;
	CPL a        ;
	mov r0, a    ;
	mov a, r1    ;       
	CPL a        ;
	mov r1, a    ;
		         ; перевод числа в доп. код для получения положительного числа
	add a, #1h   ;
	mov r1, a    ;
	mov a, r0    ;
	addc a, #0   ;
	mov r0, a    ;
exit_solve_task:

ret