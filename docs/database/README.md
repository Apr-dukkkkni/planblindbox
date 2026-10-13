# AI Planner 数据库设计说明

## 1. 设计目标

本数据库用于支持个人成长管理系统。

核心功能：

- 任务管理
- 周期习惯管理
- 时间记录
- 完成打卡
- 金币/经验/水滴奖励
- 等级成长
- 数据统计


设计原则：

1. 定义数据与执行记录分离
2. 用户资产变化必须留痕
3. 支持未来功能扩展
4. 避免过早复杂化


---

# 2. 数据模型核心思想


## 事项定义与执行记录分离


最初设计：

User

↓

Task


问题：

无法记录：

- 哪一天完成
- 完成多少次
- 连续完成天数
- 热力图数据


解决：

拆分：

Task
|
|
TaskRecord


Habit
|
|
HabitRecord



Task/Habit 保存规则。

Record 保存实际执行。


---

# 3. 设计过程中遇到的问题


## 问题1：Task是否应该包含所有任务类型


### 初始设计

所有内容放入 Task。


例如：

- 一次性任务
- 每日任务
- 周期任务
- 长期提醒


### 出现问题

不同任务生命周期不同：

一次任务：

提交论文

完成一次结束。


周期任务：

每天背单词

需要持续生成记录。


提醒：

一年后的事情

不需要每日展示。


### 解决方案

拆分：

Task:

一次性任务


Habit:

周期任务


ReminderSetting:

提醒规则



---

# 问题2：任务完成状态如何保存


### 初始设计

直接修改 Task.status。


### 问题

无法支持：

- 历史记录
- 热力图
- 连续天数


### 解决

增加：

TaskRecord

HabitRecord


例如：


Task:

学习Redis


TaskRecord:

2026-10-11 完成



---

# 问题3：金币、水滴、经验如何设计


### 初始设计

直接存任务：

Task.reward_coin


### 问题

奖励规则变化困难。


例如：

版本1：

完成任务 +10金币


版本2：

困难任务 +30金币


### 解决

增加：

RewardConfig


负责定义奖励规则。


增加：

AssetRecord


记录资产变化。


流程：

完成任务

↓

读取RewardConfig

↓

生成奖励

↓

写入AssetRecord

↓

更新UserAsset


---

# 问题4：为什么需要AssetRecord


UserAsset:

保存当前状态。


例如：

金币：

500


但是不知道来源。


AssetRecord:

记录流水。


例如：

|来源|变化|
|-|-|
|完成任务|+20金币|
|购买商品|-100金币|


方便：

- 审计
- 排查问题
- 统计


---

# 问题5：提醒设计


### 初始设计

Reminder表保存：

任务名称

提醒时间


### 问题

任务、习惯都需要提醒。


### 解决

使用：

ReminderSetting


通过：

target_type

target_id


关联：

Task

Habit


---

# 4. 当前数据库关系


User




---

# 5. 表说明


## User

用户信息


## UserAsset

用户当前资产：

- 金币
- 经验
- 水滴


## AssetRecord

资产变化流水。


## Task

一次性任务。


## TaskRecord

任务执行记录。


## Habit

周期习惯规则。


## HabitRecord

习惯每日执行记录。


## ReminderSetting

提醒配置。


## RewardConfig

奖励规则。


## LevelConfig

等级配置。


---

# 6. 后续可能扩展


## Goal

长期目标。


例如：

找到Java工作

    |
    |
    学习Redis


## Shop

商城。


## Achievement

成就。


## TimeRecord

时间统计。


目前暂不加入，避免V1过度设计。
