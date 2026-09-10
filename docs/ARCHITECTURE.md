# 架构说明

## 数据驱动

- `data/generals.json`：武将静态内容。新增武将先加数据，不改 UI。
- `data/cards.json`：基础战牌定义。
- `data/balance.json`：概率、境界名、装备品质、飞升门槛等集中参数。

## Autoload

1. `ContentDB`：加载静态内容。
2. `GameState`：唯一玩家状态源，负责资源、武将、装备、修炼、抽卡、离线结算。
3. `SaveSystem`：存档封装、校验、迁移、备份、导入导出。
4. `BattleSimulator`：在线自动牌局状态，不把逐帧战斗塞进存档。

## 为什么离线与在线分开

在线战斗要表现摸牌/杀/闪/武将机制；离线 12 小时不能逐场跑成万上亿次逻辑。因此离线用当前战力估算可推进层数和资源，装备大量掉落只保留少量，其余自动折算。

## 大数

`BigNum` 用 `mantissa + exponent` 存数值。例如 `3.82 × 10^126` 保存为：

```text
mantissa = 3.82
exponent = 126
```

战斗 HP / 伤害使用 BigNum；小型资源（原型阶段铜钱、修为）仍用 float。未来当经济数值也进入 `1e300` 级时，可把资源字段逐项迁移到同一 BigNum 序列化格式。

## 武将技能扩展路线

v0.1.0 为快速验证六个代表机制，在 `BattleSimulator` 中有显式规则适配。后续扩到 24 名完整技能时，应把这些分支迁移为独立 Skill Runtime / Hook：

- `turn_start`
- `draw_cards`
- `before_use_card`
- `transform_card`
- `before_response`
- `after_response`
- `before_damage`
- `after_damage`
- `after_card_used`
- `turn_end`

BattleSimulator 只派发事件；技能模块返回修改器。这样更新武将时不需要改主战斗流程。
