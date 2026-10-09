# 第 06 课：循环与数组

## 一、本课目标

* 掌握循环的四要素：初值、条件、循环体、步进，并能写成汇编。
* 会用 `rcx` 计数 + `inc/dec`，会用 `loop` 指令，也知道它「只认 rcx、只能短跳转」的限制。
* 会遍历 `.data` 里的 `qword` 数组：用 `[基址 + 下标*8]` 寻址，求和、统计负数、求平均值。
* 记住 **`syscall` 会破坏 `rcx`**，学会用 `push/pop` 保护计数器，或改用 `rbx/rbp/r12-r15`。
* 能识别差一错误（off-by-one）、死循环、下标当字节偏移这三类常见 bug。

## 二、新概念 / 新指令

| 概念 / 指令 | 说明 | 小例子 |
|---|---|---|
| 循环四要素 | 初值、条件、循环体、步进，缺一个就是死循环或空循环 | 见 3.1 |
| `inc` + `cmp` + `jle` | 正序计数循环（1..n） | `inc rcx` / `cmp rcx,10` |
| `dec` + `jnz` | 倒序计数循环：`dec` 会设置 ZF | `dec rcx` / `jnz .loop` |
| `loop 标号` | rcx 减 1，非 0 就跳回；**只认 rcx**，且只能短跳转 | `loop .sum` |
| `[基址 + 下标*比例]` | 数组寻址；比例只能是 1/2/4/8 | `[rbx + rbp*8]` |
| `arr_len equ ($ - arr)/8` | 汇编期算出元素个数 | 见 3.2 |
| 累加器 | 用一个寄存器存中间结果，**初值必须显式清零** | `xor r12, r12` |
| 先判断 / 后判断 | `while` 风格（可能 0 次）vs `do-while` 风格（至少 1 次） | 见下 |
| 计数器的选择 | `rcx` 会被 `syscall` 破坏；跨调用请用 `rbx/rbp/r12-r15` | `mov rbp, 0` |
| `push rcx` / `pop rcx` | 调用子程序前后保护计数器 | 见 3.1 A 段 |
| 差一错误 | `0..n-1` 还是 `1..n`，循环条件差 `<` 和 `<=` 就多跑或少跑一轮 | 见六.7 |

「先判断」和「后判断」的区别（第 05 课的条件跳转在这里派上用场）：

```asm
; while 风格：先判断，可能一次都不执行
.loop:
    cmp  rcx, 0
    jle  .done
    ...循环体...
    dec  rcx
    jmp  .loop
.done:

; do-while 风格：先做一次再判断，至少执行一次
.loop:
    ...循环体...
    dec  rcx
    jnz  .loop
```

## 三、示例源码逐段讲解

### 3.1 count.asm —— 用 rcx 数数

```asm
; ===========================================================================
; count.asm —— 计数循环：用 rcx 数数，打印 1..10、10..1，以及 loop 指令
;
; ★ 本课最重要的一条规则 ★
;   io.inc 里的每个例程内部都会执行 syscall，而 syscall 指令会把 rcx
;   和 r11 当作「返回地址/标志位暂存」来用，返回后 rcx 里就不是原来的值了。
;   所以：拿 rcx 当循环计数器时，每次调用 io 例程之前要把 rcx 压栈，
;         调用完再弹回来。不想这么麻烦就换成 rbx/rbp/r12-r15。
;
; 纯系统调用程序：入口 _start。运行： make && ./count
; ===========================================================================
default rel

section .data
    t_a db "A) rcx counter, 1..10   : "
    l_a equ $ - t_a
    t_b db "B) rcx counter, 10..1   : "
    l_b equ $ - t_b
    t_c db "C) loop: 1+2+...+100    = "
    l_c equ $ - t_c
    s_sp db " "
    l_sp equ $ - s_sp

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; A) 用 rcx 当计数器打印 1 2 3 ... 10（数字之间一个空格，末尾没有空格）
;    每次调用 io 例程前后都 push/pop rcx —— 这就是「保护计数器」
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_a]
    mov  rdx, l_a
    call io_print

    mov  rcx, 1                     ; 计数器：1 .. 10
.a_loop:
    cmp  rcx, 1
    je   .a_first                   ; 第一个数字前面不加空格
    push rcx                        ; ★ 保护计数器（syscall 会破坏 rcx）
    lea  rsi, [rel s_sp]
    mov  rdx, l_sp
    call io_print
    pop  rcx                        ; ★ 取回计数器
.a_first:
    push rcx
    mov  rdi, rcx
    call io_print_int               ; 打印计数器的值
    pop  rcx
    inc  rcx                        ; 计数器 +1
    cmp  rcx, 10
    jle  .a_loop                    ; 还没数到 10 就继续
    call io_newline

; ---------------------------------------------------------------------------
; B) 倒着数 10 9 8 ... 1：用 dec + jnz
;    dec 会设置 ZF：减到 0 时 ZF=1，jnz 就不再跳回去
;    注意 dec 不影响 CF，所以别指望用 jb/jae 判断「减到 0 了」
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_b]
    mov  rdx, l_b
    call io_print

    mov  rcx, 10
.b_loop:
    cmp  rcx, 10
    je   .b_first                   ; 第一个数字（10）前面不加空格
    push rcx
    lea  rsi, [rel s_sp]
    mov  rdx, l_sp
    call io_print
    pop  rcx
.b_first:
    push rcx
    mov  rdi, rcx
    call io_print_int
    pop  rcx
    dec  rcx                        ; 计数器 -1
    jnz  .b_loop                    ; 还不是 0 就继续
    call io_newline

; ---------------------------------------------------------------------------
; C) loop 指令：rcx 减 1，如果 rcx != 0 就跳回标号
;    loop 只认 rcx，而且比「dec rcx + jnz」慢，实际代码里前者更常用。
;    这里循环体里没有 io 调用，所以 rcx 可以放心用。
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_c]
    mov  rdx, l_c
    call io_print

    xor  rax, rax                   ; rax = 累加和 0
    mov  rcx, 100                   ; 从 100 加到 1
.c_sum:
    add  rax, rcx                   ; sum += i
    loop .c_sum                     ; rcx--；rcx != 0 就跳回 .c_sum
    mov  rdi, rax
    call io_print_int               ; 5050
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit
```

**A 段：为什么每次 `call` 前后都要 `push rcx` / `pop rcx`。**

这是本课最重要的一条规则。`io.inc` 里的例程内部都要执行 `syscall` 进入内核，
而 `syscall` 指令会把「返回地址」存进 `rcx`、把标志位存进 `r11`，所以**从系统调用返回后
`rcx` 里已经不是原来的值了**。如果把循环计数器放在 `rcx` 里，调用一次 `io_print_int`
就把它冲掉，循环次数立刻失控。

两种处理办法：

```asm
    push rcx            ; ★ 调用前把计数器存到栈上
    mov  rdi, rcx
    call io_print_int
    pop  rcx            ; ★ 调用后取回
    inc  rcx            ; 计数器步进
```

* 想省掉 push/pop，就把计数器放进 `rbx/rbp/r12-r15` —— 这些寄存器 `io.inc` 保证不破坏。
  `minmax.asm`（第 05 课）和本课 `sum_array.asm` 用的就是这种写法。

另外注意打印分隔空格的写法：`cmp rcx, 1; je .a_first` —— 第一个数字前面不加空格，
这样输出末尾就不会多一个尾随空格（否则 `test.sh` 里的字符串比较会因为一个空格失败）。

**B 段：倒着数用 `dec` + `jnz`。**

```asm
    mov  rcx, 10
.b_loop:
    ...打印...
    dec  rcx             ; 计数器 -1，并设置 ZF
    jnz  .b_loop         ; 还不是 0 就继续
```

`dec` 会自动设置 ZF，所以「减到 0 就退出」可以省掉一条 `cmp`。
但要记住第 04 课讲的：`dec` **不影响 CF**，所以别拿 `jc/jb` 去判断它。

**C 段：`loop` 指令。**

```asm
    xor  rax, rax        ; 累加和 = 0
    mov  rcx, 100
.c_sum:
    add  rax, rcx        ; sum += i
    loop .c_sum          ; rcx--；rcx != 0 就跳回
```

`loop` 等价于「`dec rcx` + `jnz`」，但有两个限制：

1. **只认 `rcx`**，不像 `jnz` 那样可以配任何比较；
2. **只有 8 位相对位移**（-128～+127 字节），循环体稍大一点就会报
   `short jump out of range`。

所以现代代码里更常见 `dec rcx` + `jnz`。这里循环体里没有任何 `io` 调用，
`rcx` 不会被破坏，可以放心用 `loop`。结果是 `1+2+…+100 = 5050`。

### 3.2 sum_array.asm —— 遍历数组

```asm
; ===========================================================================
; sum_array.asm —— 遍历 .data 里的 qword 数组：求和 / 数负数 / 求平均值
;
; 数组里故意放了负数，用来练：
;   * [基址 + 下标*8] 这种寻址方式
;   * 有符号比较（test/jns、jl、jge），别误用无符号跳转
;   * 有符号除法前的 cqo
;   * 循环计数器不能放 rcx —— syscall 会破坏它
;
; 纯系统调用程序：入口 _start。运行： make && ./sum_array
; 期望：sum = 80，count = 8，negative = 4，average = 10
; ===========================================================================
default rel

section .data
    arr     dq 10, -3, 25, -8, -1, 100, -50, 7
    arr_len equ ($ - arr) / 8       ; 8 个元素，每个 8 字节

    t_arr   db "array    : ["
    l_arr   equ $ - t_arr
    t_arr_e db "]", 10                 ; .data 里换行只能写 10（此时还没 include io.inc）
    l_arr_e equ $ - t_arr_e
    t_sum   db "sum      = "
    l_sum   equ $ - t_sum
    t_cnt   db "count    = "
    l_cnt   equ $ - t_cnt
    t_neg   db "negative = "
    l_neg   equ $ - t_neg
    t_avg   db "average  = "
    l_avg   equ $ - t_avg
    s_comma db ", "
    l_comma equ $ - s_comma

section .text
    global _start
%include "io.inc"

_start:
; ---------------------------------------------------------------------------
; 1) 打印数组内容，格式：[10, -3, 25, -8, -1, 100, -50, 7]
;    寄存器分工：
;      rbx = 数组首地址   rbp = 下标 i（这两个 io 例程都会原样保留）
;      r14 = 当前元素（先用 r14 存住，因为 io_print_int 会破坏 rax）
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_arr]
    mov  rdx, l_arr
    call io_print

    lea  rbx, [rel arr]             ; rbx → arr[0]
    xor  rbp, rbp                   ; i = 0
.prt_loop:
    cmp  rbp, arr_len
    jge  .prt_done

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]
    mov  rdi, r14
    call io_print_int

    inc  rbp
    cmp  rbp, arr_len
    jge  .prt_done                  ; 最后一个元素后面不加逗号
    lea  rsi, [rel s_comma]
    mov  rdx, l_comma
    call io_print
    jmp  .prt_loop

.prt_done:
    lea  rsi, [rel t_arr_e]
    mov  rdx, l_arr_e
    call io_print                   ; 打印 "]" 和换行

; ---------------------------------------------------------------------------
; 2) 遍历一遍，同时算出累加和与负数个数
;      r12 = sum    r13 = 负数个数    r15 = 元素总数（一会儿求平均值要用）
;    test r14, r14 后看 SF：SF=1 说明最高位是 1，也就是负数 → jns 是「非负就跳」
; ---------------------------------------------------------------------------
    xor  r12, r12                   ; sum = 0
    xor  r13, r13                   ; 负数个数 = 0
    mov  r15, arr_len               ; 元素总数
    lea  rbx, [rel arr]
    xor  rbp, rbp                   ; i = 0

.sum_loop:
    cmp  rbp, r15
    jge  .sum_done

    mov  r14, [rbx + rbp*8]         ; r14 = arr[i]
    add  r12, r14                   ; sum += arr[i]

    test r14, r14
    jns  .not_neg                   ; SF=0 → 不是负数，跳过计数
    inc  r13
.not_neg:
    inc  rbp
    jmp  .sum_loop

.sum_done:
    ; ---- 打印 sum ----
    lea  rsi, [rel t_sum]
    mov  rdx, l_sum
    call io_print
    mov  rdi, r12
    call io_print_int
    call io_newline

    ; ---- 打印 count ----
    lea  rsi, [rel t_cnt]
    mov  rdx, l_cnt
    call io_print
    mov  rdi, r15
    call io_print_int
    call io_newline

    ; ---- 打印 negative ----
    lea  rsi, [rel t_neg]
    mov  rdx, l_neg
    call io_print
    mov  rdi, r13
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 3) 平均值 = sum / count
;    80 / 8 = 10；被除数和除数都在寄存器里，除法前必须 cqo（有符号）
;    如果这里错写成 xor rdx,rdx（无符号那套），负数数组就会得到荒唐的结果
; ---------------------------------------------------------------------------
    lea  rsi, [rel t_avg]
    mov  rdx, l_avg
    call io_print

    mov  rax, r12                   ; 被除数 = sum
    cqo                             ; ★ 有符号除法：把符号位扩展到 rdx
    idiv r15                        ; rax = sum / count
    mov  rdi, rax
    call io_print_int
    call io_newline

; ---------------------------------------------------------------------------
; 结束进程
; ---------------------------------------------------------------------------
    xor  edi, edi
    call io_exit
```

**数组定义与长度。**

```asm
    arr     dq 10, -3, 25, -8, -1, 100, -50, 7
    arr_len equ ($ - arr) / 8
```

`dq` 给每个元素分配 8 字节，`$ - arr` 是数组的总字节数（64），除以 8 得到元素个数 8。
**除数一定要写元素大小**：如果数组是 `dd`（4 字节）却除以 8，元素个数就会算错一半。

**寄存器分工表**（这是本课的核心技巧）：

| 寄存器 | 用途 | 为什么选它 |
|---|---|---|
| `rbx` | 数组首地址 | `io.inc` 不破坏 |
| `rbp` | 下标 `i` | `io.inc` 不破坏（它只在 `io_print_uint` 里被 push/pop 保护） |
| `r12` | 累加和 sum | `io.inc` 不破坏 |
| `r13` | 负数个数 | `io.inc` 不破坏 |
| `r14` | 当前元素 | 打印前先把元素搬进这里，避免被 `rax` 的破坏波及 |
| `r15` | 元素总数 | 求平均值时当除数 |

反过来说，`rax/rcx/rdx/rsi/rdi/r11` 在 `io.inc` 调用之后都不能信（`rax` 是返回值、
`rcx`/`r11` 被 `syscall` 破坏、`rdx` 被数字打印例程内部占用来做除法）。
这就是「被调用者保存（callee-saved）」和「调用者保存（caller-saved）」的区别，
第 07 课讲函数时会正式定义这两个词。

**遍历、求和、判定负数。**

```asm
.sum_loop:
    cmp  rbp, r15
    jge  .sum_done              ; 先判断：下标走完就退出（先判断循环）
    mov  r14, [rbx + rbp*8]     ; r14 = arr[i]
    add  r12, r14               ; sum += arr[i]
    test r14, r14
    jns  .not_neg               ; SF=0 → 非负，跳过计数
    inc  r13
.not_neg:
    inc  rbp
    jmp  .sum_loop
```

* `[rbx + rbp*8]` 里乘 8 是「下标 → 字节偏移」的换算，由 CPU 免费完成。写成
  `[rbx + rbp]` 就变成读第 `rbp` 个**字节**，取出来的是错位数据（这正是常见坑 5）。
* `test r14, r14` + `jns`：`test` 取 `r14 & r14`，结果就是 `r14` 本身，
  所以 SF 等于元素的最高位；`jns`（SF=0）表示非负。等价写法是 `cmp r14, 0` + `jge`。

**求平均值要注意有符号除法。**

```asm
    mov  rax, r12               ; 被除数 = sum
    cqo                         ; ★ 有符号：符号位扩展到 rdx
    idiv r15                    ; rax = sum / count
```

数组里有负数时 `sum` 是**有符号**量，这里必须用 `cqo + idiv`；
如果错写成 `xor rdx, rdx + div`，负数会被当成巨大的无符号数，结果离谱。

最终输出：`sum = 80`、`count = 8`、`negative = 4`、`average = 10`。

## 四、编译与运行

```bash
cd lesson06
make
./count
./sum_array
make test
```

`./count` 的真实输出：

```text
A) rcx counter, 1..10   : 1 2 3 4 5 6 7 8 9 10
B) rcx counter, 10..1   : 10 9 8 7 6 5 4 3 2 1
C) loop: 1+2+...+100    = 5050
```

`./sum_array` 的真实输出：

```text
array    : [10, -3, 25, -8, -1, 100, -50, 7]
sum      = 80
count    = 8
negative = 4
average  = 10
```

## 五、动手练习

1. 把 `count.asm` 的 A 段改成打印 `1..20`，B 段改成打印 `5 4 3 2 1`。
2. 把 C 段的 100 改成 1000（结果是 500500），然后试着在 `loop` 的循环体里加一句
   `call io_print_int`，观察/解释为什么结果不对，再用 `dec rcx` + `jnz` 加 `push/pop`
   的方式把它改对。
3. 在 `sum_array.asm` 里增加两个统计：正数个数、零的个数，并打印出来。
4. 把数组里所有负数取绝对值后再求和（提示：`neg` 之前先判断是不是负数）。
5. 计算数组里最大值及其下标（下标从 0 开始，最大值有多个时取第一个出现的）。
6. 用循环打印斐波那契数列的前 10 项（1 1 2 3 5 8 …），每项用 `io_print_int` 输出。

练习 5 提示：用 `rbp` 当遍历下标，另外拿一个空闲寄存器（比如 `r15`）记住「当前最大值的下标」，
每发现「更严格地更大」才同时更新最大值和它的下标 —— 用 `jg`（严格大于）而不是 `jge`，
才能保证取到的是第一个最大值。

练习 6 提示：斐波那契要三个寄存器（前一项、当前项、下一项），
循环次数用 `rbp` 之类不会被 `io` 破坏的寄存器来数，
每次进入循环体先算出下一项再打印，注意别把「要保留的值」放在 `rax` 里。

## 六、常见坑

1. **把循环计数器放在 `rcx` 里还调用 `io.inc`**：`syscall` 破坏 `rcx`，循环立刻失控。
   这是本课最容易踩、也最难靠「看代码」发现的坑。对策：`push/pop` 保护，或者干脆用
   `rbx/rbp/r12-r15`。
2. **`push` 和 `pop` 不配对**：`push rcx` 之后走了别的分支没 `pop`，或者 `pop` 了两次，
   会让 `rsp` 错位。本课的程序最后都走 `io_exit`（直接结束进程），不会崩；
   但第 07 课开始用 `ret` 返回，栈一错位就立刻段错误。
3. **`loop` 只能短跳转**：循环体超过 128 字节就报 `short jump out of range`，
   此时必须换成 `dec rcx` + `jnz`（后者用 32 位位移，能跳很远）。
4. **`loop` 不改标志位，`dec` 改**：`loop` 之后想用 `jz` 判断「rcx 减到 0 了」是不行的，
   它只把控制流带走。
5. **下标当字节偏移**：`dq` 数组必须写成 `[rbx + rbp*8]`；
   `[rbx + rbp]`、`[rbx + rbp*4]` 都能汇编通过，但读出来的是错位数据。
6. **`arr_len` 忘了除以元素大小**：`equ ($ - arr) / 8` 里的 8 必须和 `dq` 对应。
7. **差一错误**：`1..10` 用 `jle`（≤10，共 10 次），`0..n-1` 用 `jl`（<n，共 n 次）。
   条件写成 `jl` 却从 1 开始数，就会少打一个 10。
8. **死循环**：忘了 `inc/dec`、条件跳转的目标写成自己、或者比较条件写反
   （`jle` 写成 `jge`）。本课所有程序都在 1 秒内结束，如果 `./count` 挂住不返回，
   按 `Ctrl+C`，然后检查这三处。
9. **累加器没清零**：`rax`/`r12` 在进程启动时的值是不确定的，`add` 之前必须先 `xor` 清零。
10. **有符号统计用错跳转**：统计负数、比较元素大小要用 `jl/jg/jge`（本课 `jns` 也是看 SF），
    用 `jb/ja` 会把负数当成大正数。
11. **有符号除法忘记 `cqo`**：数组元素有负数时 `sum` 可能为负，`idiv` 之前必须 `cqo`。
