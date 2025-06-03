# CULMod - 《求生之路2》（L4D2）中国高校竞技配置 (基于Zonemod)
### 作者: 40407, 184noob
### 特别鸣谢: Visor, Jahze, ProdigySim, Vintik, CanadaRox, Blade, Tabun, Jacob, Forgetest, A1m，Sir
### ZoneMod竞技配置框架是必要的: https://github.com/SirPlease/L4D2-Competitive-Rework/
##
### "MatchModes"
### {
### &emsp;"CULMod Configs"
### &emsp;{
### &emsp;&ensp;"cmpr"
### &emsp;&ensp;{
### &emsp;&emsp;"name" "CULMod Pro"
### &emsp;&ensp;}
### &emsp;&ensp;"cmel"
### &emsp;&ensp;{
### &emsp;&emsp;"name" "CULMod Elite"
### &emsp;&ensp;}
### &emsp;&ensp;"culmod"
### &emsp;&ensp;{
### &emsp;&emsp;"name" "CULMod Noob"
### &emsp;&ensp;}
### &emsp;}
### }
##
## CULMod Pro
### 奖励分同zm
### 1. UZI 64发
### 2. 新增MP5
### 3. 铁喷7发；喷子扩散减少
### 4. 每回退7%，克控锁5s
##
## CULMod Elite
### 包分 = 0.1 * 路程分 * n 
### 药分 = 0.05 * 路程分 * n 
### 伤害分 =（540 - 伤害计数）* 路程分/300 
### 倒地 +54 伤害计数，扶起 -30 伤害计数 
### 1. uzi： 
### 伤害 23 
### 移动最小扩散0.2 
### 移动最大扩散1.9
### 衰减系数0.8
### smg:
### 换弹1.9s
### 衰减系数0.75
### 2. 铁喷弹丸伤害30，木喷18 
### 3. 小僵尸上限25 
### ①胖子喷第一第二人：11个 
### ②第三第四人：9个 
### 4. 机枪备弹950 , 喷备弹128 
### 5. 近战砍牛300 
### 6. 包回血60%,打包时间4s 
### 7. 生还者每回退7%,坦克控制权冻结5s，克6300
##
## CULMod Noob
### 1.奖励分：
### ① 总血分＝路程分
### ② 一个包＝路程分÷团队人数×0.8
### ③ 死亡惩罚=路程分÷团队人数
### 2. uzi：
### 伤害 22->23
### 移动最小扩散0.2
### 移动最大扩散1.85
### 衰减系数0.8
### 3. smg:
### 装弹速度1.8s
### 移动最大扩散2.3
### 衰减系数0.85
### 4. 铁喷:弹丸伤害29
### 5. 喷子最高友伤:8->5
### 6. 小僵尸数量30->20
### ①胖子喷第一人12个->9个
### ②第二人：13个->10个
### ③第三第四人：10个->8个
### 7. 机枪
### 弹夹:60
### 备弹:900
### 8. 喷备弹:100
