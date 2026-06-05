# DNAsm 语法教程 -- DNA原生编程入门

## 一句话概括

传统编程：变量 = 数字，存内存里  
DNA编程：试管 = 浓度，浓度 = 数值  

一条DNA链有N个拷贝 = 数值N  
PCR扩增（COPY）= 乘法  
两管合并（ADD）= 加法  
限制酶切（CLEAVE）= 对数衰减  
链置换（DISPL）= 条件判断  

## 核心概念：试管 = 变量

```
传统语言          DNAsm
--------          -----
int x = 1000;    NUM st[0] 1000
int y = 500;     NUM st[1] 500
int z = x + y;   ADD st[0] st[1]   // st[0] = 1500
z = z * 4;       COPY st[0] 2      // PCR 2轮 = *4
print(z);        PRINT st[0]
```

## 完整指令集

### 数值操作
```
NUM st[k] N       -- 往试管k里加N条标记链（设置数值）
COPY st[k] C      -- PCR扩增C轮（数值 * 2^C）
ADD st[dst] st[src]  -- 把src试管浓度倒入dst（加法）
SUB st[dst] st[src]  -- 减法
MUL st[dst] st[src]  -- 乘法
DIV st[dst] st[src]  -- 整数除法
PRINT st[k]       -- 读取数值（荧光检测）
```

### 分子操作（DNA原生）
```
LOAD st[k] "ATGC..."  -- 往试管里加入特定DNA序列
UNZIP st[k]         -- 解链（双链→两条单链）
HYB st[k]           -- 退火杂交（互补单链→双链）
DISPL st[k] "ATGC"  -- 链置换（入侵链替换）
CLEAVE st[k] "ACGT" -- 限制酶切（在特定位点切断）
LIGATE st[k] st[a] st[b]  -- DNA连接酶拼接
POLY st[dst] st[src] "AT" -- 聚合酶复制
ANNEAL st[k] 37.0   -- 退火（低温让链配对）
MELT st[k] 95.0     -- 熔解（高温让链分开）
```

### 数学函数
```
FIB st[k] N       -- 计算第N个斐波那契数
FACT st[k] N      -- 计算N的阶乘
PRIME st[k] N     -- 计算不超过N的素数个数
POW st[k] E       -- 计算st[k]^E
SQRT st[k]        -- 整数平方根
GCD st[dst] st[src]  -- 最大公约数
LUCAS P           -- Lucas-Lehmer测试M_p是否为素数
```

### 系统操作
```
BURN st[k]        -- 清空试管（销毁所有链）
READ st[k]        -- 读取试管内容（显示DNA序列）
HALT              -- 程序结束
```

## 举个例子：计算 1+2+3+...+100

```dna
# sum.dna -- 计算1到100的和
NUM st[0] 5050    # 直接设置结果（5050=100*101/2）
PRINT st[0]       # 输出 5050
HALT
```

或者一步步算：
```dna
# sum_loop.dna -- 用加法循环
NUM st[0] 0       # sum = 0
NUM st[1] 1       # i = 1
NUM st[2] 1       # 常量1
NUM st[3] 100     # 上限100

# 手动展开循环（因为当前没有JMP指令）
ADD st[0] st[1]   # sum += i
ADD st[1] st[2]   # i += 1
ADD st[0] st[1]   # sum += i
ADD st[1] st[2]   # i += 1
# ... 重复100次

PRINT st[0]       # 输出 5050
HALT
```

## 再举个例子：Gram点（黎曼零点近似）

```dna
# gram.dna -- 计算第100万个黎曼零点的近似位置
# 公式：t_n = 2*pi*n / ln(n)
# n=1,000,000 时，t ≈ 454,800

NUM st[0] 1000000   # n = 1,000,000
COPY st[0] 1        # PCR 1轮 = *2 → 2,000,000
NUM st[1] 3141      # pi ≈ 3.14159 (乘以1000)
MUL st[0] st[1]     # 2,000,000 * 3141 = 6,282,000,000
NUM st[1] 13816     # ln(1000000) ≈ 13.8155 (乘以1000)
DIV st[0] st[1]     # 6,282,000,000 / 13816 ≈ 454,690
PRINT st[0]         # 输出 ~454,690
HALT
```

## 与递砖机D1-D4的映射

| 递砖机步骤 | DNAsm实现 | 含义 |
|-----------|----------|------|
| D1 Capture | `NUM st[k] N` | 编码输入N为试管浓度 |
| D2 Turan | `COPY + ADD + MUL` | PCR扩增（乘）+浓度合并（加） |
| D3 Berry | `CLEAVE + SQRT` | 对数衰减+误差估计 |
| D4 Loop | `PRINT`迭代输出 | 递砖循环输出结果 |

## 文件编码

.dna文件是纯文本，一行一条指令。
编译后输出DNA碱基序列（每条指令=3个碱基）。

```
NUM  →  ACT
COPY →  AGG
ADD  →  AGA
SUB  →  AGT
...
```

## 运行方式

```bash
# 编译+运行
cd ~/DNAOS && ./dnaos2 program.dna

# 或分步
dnasm3 program.dna      # 编译为 output.dna（碱基序列）
./dnaos2 output.dna     # 执行
```
