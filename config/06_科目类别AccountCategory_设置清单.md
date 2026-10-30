# 06 科目类别（Account Category）设置清单

> ⚠️ **这份文件是 05 号导入模板的必配套步骤，不能跳过。**
> 原因：ERPNext 官方科目表导入模板是**固定 8 列**（源码 `chart_of_accounts_importer.py` 里 `no_of_columns != 8` 直接报错），
> **这 8 列里没有 Account Category 这一列**。所以科目类别必须在导入之后单独设置。
> **不设的后果：自定义财务报表模板里对应行全部显示 0，资产负债表永远不平。**

---

## 一、先理解：Account Type 和 Account Category 是两个不同的东西

| 字段 | 作用 | 谁在用 |
|---|---|---|
| **Account Type** | 决定这个科目的**业务行为**（能不能挂客户/供应商、能不能算库存、算不算固定资产） | ERPNext 的**业务逻辑**依赖它 |
| **Account Category** | 决定这个科目在**财务报表里归到哪一行** | ERPNext 的**财务报表模板**依赖它 |

**关键事实**：

> **ERPNext 的标准报表能靠 `Root Type` 自动归类出数；但自定义报表模板（Financial Report Template）强依赖 `Account Category`。**

这就是为什么很多人"科目建好了、凭证也录了，自定义资产负债表却是空的"。

---

## 二、三条铁律（违反任一条，报表就会出错）

| # | 铁律 | 后果 |
|---|---|---|
| 1 | ⭐ **只给末级科目设（Is Group = 0）** | 给分组科目设会导致重复计算，金额翻倍 |
| 2 | ⭐ **名称必须与报表模板里选的完全一致** | 差一个大小写、多一个空格，该行就是 0 |
| 3 | ⚠️ **"本年利润"绝对不能设任何类别** | 它被利润表自动使用，设了会被算两遍，**资产负债表永远不平** |

---

## 三、建议映射表（对照 05 号模板的科目）

> ⚠️ **重要**：Account Category 的**实际可选值以你系统里的列表为准**
> （路径：`Accounting → Account Category` 或直接搜索 `Account Category`）。
> 不同 ERPNext 版本预置的类别名称可能有差异，**配置报表时请从下拉框里选，不要手打**。

| 科目编码 | 科目名称 | 建议 Account Category |
|---|---|---|
| 1001 | 库存现金 | Cash and Cash Equivalents |
| 1002 | 银行存款 | Cash and Cash Equivalents |
| 1012 | 其他货币资金 | Cash and Cash Equivalents |
| 1121 | 应收票据 | Other Receivables |
| 1122 | 应收账款 | Trade Receivables |
| 1123 | 预付账款 | Other Receivables |
| 1221 | 其他应收款 | Other Receivables |
| 1403 | 原材料 | Stock Assets |
| 1405 | 库存商品 | Stock Assets |
| 1411 | 周转材料 | Stock Assets |
| 1471 | 存货跌价准备 | Current Assets |
| 1511 | 长期股权投资 | Non-Current Assets |
| 1601 | 固定资产 | Fixed Assets |
| 1602 | 累计折旧 | Accumulated Depreciation（如无此项，归 Non-Current Assets） |
| 1604 | 在建工程 | Capital Work in Progress |
| 1701 | 无形资产 | Fixed Assets |
| 1702 | 累计摊销 | Accumulated Depreciation（同上） |
| 1801 | 长期待摊费用 | Non-Current Assets |
| 2001 | 短期借款 | Current Liabilities |
| 2201 | 应付票据 | Other Payables |
| 2202 | 应付账款 | Trade Payables |
| 2203 | 预收账款 | Other Payables |
| 2211 | 应付职工薪酬 | Current Liabilities |
| 2221 | 应交税费 | Current Liabilities |
| 222101~222108 | 应交税费各明细 | Current Liabilities |
| 2241 | 其他应付款 | Other Payables |
| 2501 | 长期借款 | Non-Current Liabilities |
| 2801 | 预计负债 | Non-Current Liabilities |
| 4001 | 实收资本 | Equity |
| 4002 | 资本公积 | Equity |
| 4101 | 盈余公积 | Equity |
| **4103** | **本年利润** | ⚠️ **留空，不要设** |
| 4104 | 利润分配 | Equity |
| 6001 | 主营业务收入 | Revenue |
| 6051 | 其他业务收入 | Revenue |
| 6111 | 投资收益 | Revenue |
| 6301 | 营业外收入 | Revenue |
| 6401 | 主营业务成本 | Cost of Goods Sold |
| 6402 | 其他业务成本 | Cost of Goods Sold |
| 6403 | 税金及附加 | Operating Expenses |
| 6601 | 销售费用 | Operating Expenses |
| 6602 | 管理费用 | Operating Expenses |
| 6603 | 财务费用 | Operating Expenses |
| 6711 | 营业外支出 | Operating Expenses |
| 6801 | 所得税费用 | Operating Expenses |

---

## 四、设置方法（三种，按效率排序）

### 方法 1：Tree View 批量设（推荐）

1. 打开 `Accounting → Chart of Accounts`
2. 右上角切到 **Tree View**
3. 在树里逐个点开末级科目，在右侧表单里设 `Account Category` 并保存
4. 或用 **List View** 批量勾选 → 但 Account Category 不能批量编辑，需逐个处理

### 方法 2：用 ERPNext 自带的更新工具

新版 ERPNext 有 `Update Account Category` 工具（在 Accounting 模块搜索），可按规则批量刷新末级科目的类别。

> 💡 如果你用的是 v15.32.0，先搜一下这个工具在不在；不在就用手工方式。

### 方法 3：直接写数据库（不推荐，仅限批量场景）

```sql
-- ⚠️ 执行前务必备份数据库
UPDATE `tabAccount`
SET account_category = 'Trade Receivables'
WHERE account_number = '1122' AND company = '你的公司名' AND is_group = 0;
```

---

## 五、设置完成后的验证

| # | 检查项 | 方法 |
|---|---|---|
| 1 | 所有末级科目都有类别（除"本年利润"） | 查 `tabAccount` 里 `is_group=0 AND (account_category IS NULL OR account_category='')` |
| 2 | "本年利润"确实为空 | 单独确认 |
| 3 | 分组科目都没设类别 | 查 `is_group=1 AND account_category IS NOT NULL` |

```sql
-- 验证 SQL（在 ERPNext 的 Query Report / 数据库客户端里跑）
SELECT name, account_name, is_group, account_category
FROM `tabAccount`
WHERE company = '你的公司名'
  AND is_group = 0
  AND (account_category IS NULL OR account_category = '');
```

---

## 六、正确顺序（千万别搞反）

```
1. 导入科目表（05 号 CSV）
        ↓
2. 设置 Account Category（本文件）      ← 很多人跳过这步
        ↓
3. 配置三大报表模板（02 号文件）
        ↓
4. 录入期初余额 / 开始记账
```

> ⚠️ **如果你已经录了业务数据**，再改科目表会非常麻烦（ERPNext 会拒绝有交易的科目表导入）。所以**顺序一定要在开账前做对**。
