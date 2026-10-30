-- =====================================================================
-- 07 研发费用辅助账 —— ERPNext Query Report SQL
-- 适用：ERPNext v15.x（表结构与字段名基于 v15）
-- 用途：按"研发项目"维度归集研发费用，输出符合高企认定 / 加计扣除口径的辅助账
-- =====================================================================


-- =====================================================================
-- 【使用前必做：三步准备】
-- =====================================================================
--
-- 第 1 步：创建会计维度（Accounting Dimension）
--   路径：Accounting → Accounting Dimensions → New
--   - Dimension Name 建议填：研发项目
--   - 系统会自动在 `tabGL Entry` 上新建一个字段
--
--   ⚠️ 关键：确认这个字段的【实际 fieldname】是什么，下面 SQL 里要替换。
--   因为维度的 fieldname 由 frappe.scrub(维度名) 生成，中文维度名可能原样保留，
--   也可能被改名，必须以实际为准。用下面这句查：
--
--     SELECT COLUMN_NAME, COLUMN_COMMENT
--     FROM INFORMATION_SCHEMA.COLUMNS
--     WHERE TABLE_NAME = 'tabGL Entry'
--       AND COLUMN_NAME NOT IN (
--         'name','creation','modified','modified_by','owner','docstatus','idx',
--         'posting_date','account','account_currency','party_type','party',
--         'voucher_type','voucher_no','against_voucher_type','against_voucher',
--         'cost_center','project','company','debit','credit',
--         'debit_in_account_currency','credit_in_account_currency',
--         'is_opening','is_advance','fiscal_year','remarks','is_cancelled','is_ambiguous'
--       );
--
--   查到后，把下面所有 `gle.研发项目` 替换成真实的 `gle.<字段名>`。
--
-- 第 2 步：建立"研发费用科目"与"费用类别"的对照
--   下面 SQL 用科目编码前两位/前四位来判断费用类别，你需要按自己公司的科目编码改。
--
-- 第 3 步：新建 Query Report
--   路径：Report → New Report → Report Type 选 "Query Report"
--   把本文件里需要的 SQL 粘进去，保存
--
-- =====================================================================


-- =====================================================================
-- 【报表 1】研发费用辅助账汇总表（按项目 × 8 类费用）
-- 对应高企认定 / 加计扣除的"研发费用辅助账"主表
-- 报表过滤器（Filters）：company, from_date, to_date
-- =====================================================================

SELECT
    gle.研发项目                                                    AS `研发项目:Link/研发项目:180`,
    SUM(CASE WHEN acc.account_number LIKE '6602%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `一、人员人工:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '1403%'
              OR acc.account_number LIKE '6402%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `二、直接投入:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '1602%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `三、折旧费用:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '1702%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `四、无形资产摊销:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '6604%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `五、新产品设计费:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '6605%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `六、装备调试费:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '6606%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `七、委托外部研发:Currency:130`,
    SUM(CASE WHEN acc.account_number LIKE '6699%' THEN gle.debit - gle.credit ELSE 0 END)
                                                                    AS `八、其他费用:Currency:130`
FROM `tabGL Entry` gle
INNER JOIN `tabAccount` acc ON acc.name = gle.account
WHERE
    gle.company = %(company)s
    AND gle.is_cancelled = 0
    AND gle.docstatus = 1
    AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
    AND IFNULL(gle.研发项目, '') != ''
GROUP BY gle.研发项目
ORDER BY gle.研发项目

-- ⚠️ 说明：
--   1) 上面用 `account_number LIKE '6602%'` 只是**示例判断方式**，你必须
--      按自己公司的科目编码体系改成实际规则（也可以用 account_name LIKE）。
--   2) 研发费用通常同时挂"研发项目"和"费用类别"两个维度，
--      更严谨的做法是再加一个"研发费用类别"会计维度，用它来分类，最准确。
--   3) `Income:Currency:130` 里的 130 是列宽，可自行调整。


-- =====================================================================
-- 【报表 2】研发费用辅助账明细表（可追溯到凭证）
-- 税务/审计核查时要能"从辅助账查到凭证"，这张表是必备的
-- 报表过滤器（Filters）：company, from_date, to_date, research_project
-- =====================================================================

SELECT
    gle.posting_date                    AS `记账日期:Date:100`,
    gle.voucher_type                    AS `凭证类型:Link/DocType:120`,
    gle.voucher_no                      AS `凭证号:Dynamic Link/voucher_type:180`,
    acc.account_number                  AS `科目编码:Data:100`,
    acc.account_name                    AS `科目名称:Data:180`,
    gle.研发项目                        AS `研发项目:Link/研发项目:160`,
    gle.cost_center                     AS `成本中心:Link/Cost Center:140`,
    IFNULL(gle.debit, 0)                AS `借方:Currency:120`,
    IFNULL(gle.credit, 0)               AS `贷方:Currency:120`,
    gle.remarks                         AS `摘要:Data:240`
FROM `tabGL Entry` gle
INNER JOIN `tabAccount` acc ON acc.name = gle.account
WHERE
    gle.company = %(company)s
    AND gle.is_cancelled = 0
    AND gle.docstatus = 1
    AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
    AND IFNULL(gle.研发项目, '') != ''
    AND (%(research_project)s IS NULL
         OR %(research_project)s = ''
         OR gle.研发项目 = %(research_project)s)
    AND acc.root_type = 'Expense'
ORDER BY gle.研发项目, gle.posting_date, gle.voucher_no


-- =====================================================================
-- 【报表 3】研发费用占比检查表（双口径）
-- 用途：自动算出"其他费用"占比，对照两个不同上限做预警
--   加计扣除口径：其他费用 ≤ 可加计扣除总额的 10%
--   高企认定口径：其他费用 ≤ 研发总费用的 20%
-- =====================================================================

SELECT
    t.研发项目                                              AS `研发项目:Link/研发项目:180`,
    t.研发总额                                              AS `研发费用总额:Currency:150`,
    t.其他费用                                              AS `其中其他费用:Currency:150`,
    ROUND(t.其他费用 / NULLIF(t.研发总额, 0) * 100, 2)      AS `其他费用占比(%):Float:130`,
    CASE
        WHEN t.其他费用 / NULLIF(t.研发总额, 0) > 0.20 THEN '超双口径上限'
        WHEN t.其他费用 / NULLIF(t.研发总额, 0) > 0.10 THEN '超加计扣除上限(10%)，未超高企(20%)'
        ELSE '正常'
    END                                                     AS `预警:Data:260`
FROM (
    SELECT
        gle.研发项目 AS 研发项目,
        SUM(gle.debit - gle.credit) AS 研发总额,
        SUM(CASE WHEN acc.account_number LIKE '6699%'
                 THEN gle.debit - gle.credit ELSE 0 END) AS 其他费用
    FROM `tabGL Entry` gle
    INNER JOIN `tabAccount` acc ON acc.name = gle.account
    WHERE
        gle.company = %(company)s
        AND gle.is_cancelled = 0
        AND gle.docstatus = 1
        AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
        AND IFNULL(gle.研发项目, '') != ''
        AND acc.root_type = 'Expense'
    GROUP BY gle.研发项目
) t
ORDER BY t.研发项目


-- =====================================================================
-- 【报表 4】未挂研发项目的费用检查表（数据质检用）
-- 用途：找出"看起来是研发支出、但没打研发项目标签"的凭证
--       这类漏标会导致研发费用被低估，加计扣除时吃亏
-- =====================================================================

SELECT
    gle.posting_date        AS `记账日期:Date:100`,
    gle.voucher_type        AS `凭证类型:Link/DocType:120`,
    gle.voucher_no          AS `凭证号:Dynamic Link/voucher_type:180`,
    acc.account_number      AS `科目编码:Data:100`,
    acc.account_name        AS `科目名称:Data:180`,
    gle.cost_center         AS `成本中心:Link/Cost Center:140`,
    IFNULL(gle.debit, 0) - IFNULL(gle.credit, 0) AS `金额:Currency:120`,
    gle.remarks             AS `摘要:Data:240`
FROM `tabGL Entry` gle
INNER JOIN `tabAccount` acc ON acc.name = gle.account
WHERE
    gle.company = %(company)s
    AND gle.is_cancelled = 0
    AND gle.docstatus = 1
    AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
    AND acc.root_type = 'Expense'
    AND acc.account_number LIKE '66%'          -- 按你的研发/管理费用科目范围改
    AND IFNULL(gle.研发项目, '') = ''          -- 未打研发项目标签
    AND gle.debit > 0
ORDER BY gle.posting_date DESC


-- =====================================================================
-- 【附表 A】委托研发 80% 折算计算
-- 政策：委托外部研发按实际发生额的 80% 计入研发费用
-- =====================================================================

SELECT
    gle.研发项目                                        AS `研发项目:Link/研发项目:180`,
    SUM(gle.debit - gle.credit)                         AS `委托研发实际发生额:Currency:160`,
    ROUND(SUM(gle.debit - gle.credit) * 0.8, 2)         AS `可按80%计入:Currency:150`,
    ROUND(SUM(gle.debit - gle.credit) * 0.2, 2)         AS `不可计入部分:Currency:140`
FROM `tabGL Entry` gle
INNER JOIN `tabAccount` acc ON acc.name = gle.account
WHERE
    gle.company = %(company)s
    AND gle.is_cancelled = 0
    AND gle.docstatus = 1
    AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
    AND IFNULL(gle.研发项目, '') != ''
    AND acc.account_number LIKE '6606%'      -- 委托外部研发科目
GROUP BY gle.研发项目


-- =====================================================================
-- 【附表 B】按月发生额（用于"按月登记、按月核对"）
-- 税法要求辅助账按月登记，不能年底集中补
-- =====================================================================

SELECT
    DATE_FORMAT(gle.posting_date, '%%Y-%%m')            AS `月份:Data:100`,
    gle.研发项目                                        AS `研发项目:Link/研发项目:180`,
    SUM(gle.debit - gle.credit)                         AS `当月发生额:Currency:150`,
    COUNT(*)                                            AS `凭证笔数:Int:100`
FROM `tabGL Entry` gle
INNER JOIN `tabAccount` acc ON acc.name = gle.account
WHERE
    gle.company = %(company)s
    AND gle.is_cancelled = 0
    AND gle.docstatus = 1
    AND gle.posting_date BETWEEN %(from_date)s AND %(to_date)s
    AND IFNULL(gle.研发项目, '') != ''
    AND acc.root_type = 'Expense'
GROUP BY DATE_FORMAT(gle.posting_date, '%%Y-%%m'), gle.研发项目
ORDER BY 月份, gle.研发项目

-- ⚠️ 注意 `%%Y-%%m`：在 ERPNext Query Report 里，百分号需要写成两个 `%%`，
--    因为底层会用 % 做参数替换，单个 % 会被吃掉。


-- =====================================================================
-- 【重要提醒】
-- =====================================================================
--
-- 1) 会计维度字段名必须替换成实际的（见文件开头第 1 步查询方法）。
--
-- 2) 科目编码映射必须按你公司的科目表改。上面的 LIKE 规则只是示例。
--
-- 3) 研发费用辅助账的成败 90% 取决于"工时记录是否真实"，
--    不在 SQL。建议用管理手段（不填工时不能报销/不能提交工时对应单据）
--    保证数据源头质量。
--
-- 4) 税法要求：
--    - 辅助账按项目设置，按 8 类费用设明细
--    - 按月登记、按月核对，不能年底集中补
--    - 辅助账汇总数 = 财务报表 = 所得税申报表（三方一致）
--    - 研发费用与生产经营费用必须严格隔离
--
-- 5) 委托研发需备齐：委托合同、付款凭证、成果归属证明，
--    且只能按实际发生额的 80% 计入。
--
-- 6) 其他费用：
--    - 加计扣除口径 ≤ 可加计扣除总额的 10%
--    - 高企认定口径 ≤ 研发总费用的 20%
--    两个口径不同，报表要分两列显示。
