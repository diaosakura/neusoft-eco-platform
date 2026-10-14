-- ============================================================================
--  东软空气质量环保公众监督系统 —— 数据库结构（8 张表，手动一键版）
--  依据：《需求进度管理表》及评审意见（表数量控制在 10 张以内）
--  数据库：MySQL 8.0   字符集：utf8mb4   引擎：InnoDB
--
--  执行方式：mysql -u root -p < sql/air_quality_schema.sql
--
--  与初版 15 张表的调整：
--    1. 省/市/区县三表合并为 sys_region（parent_id + region_level 自关联）
--    2. 账号/监督员信息/网格员信息三表合并为 sys_user（role_code 区分角色）
--    3. 取消角色表，角色用 sys_user.role_code 表示
--    4. 取消指派记录表，指派历史由 feedback_order.assignee_id + oper_log 追溯
--    5. 统计数据表与指标汇总表合并为 aqi_statistics（stat_type 区分口径）
--
--  ⚠️ 与 src/main/resources/sql/schema.sql 是同一套表结构的两份拷贝：
--     后者是应用启动时自动执行的版本（不含建库语句），本文件是「手动一键版」。
--     改表结构时两处都要改，否则会漂移。演示数据不包含在本文件中，
--     由应用启动时执行 data.sql，或手动执行 src/main/resources/sql/data.sql。
-- ============================================================================

CREATE DATABASE IF NOT EXISTS neusoft_eco
    DEFAULT CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

USE neusoft_eco;

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- ---------------------------------------------------------------------------
--  清理初版（15 张表）中已被合并或取消的表
--  sys_role/supervisor_info/grid_manager_info      -> 已并入 sys_user
--  sys_province/sys_city/sys_district              -> 已合并为 sys_region
--  feedback_assign                                 -> 派历史改由 oper_log 追溯
--  aqi_stat_summary                                -> 已并入 aqi_statistics
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS sys_role;
DROP TABLE IF EXISTS sys_province;
DROP TABLE IF EXISTS sys_city;
DROP TABLE IF EXISTS sys_district;
DROP TABLE IF EXISTS supervisor_info;
DROP TABLE IF EXISTS grid_manager_info;
DROP TABLE IF EXISTS feedback_assign;
DROP TABLE IF EXISTS aqi_stat_summary;

-- ---------------------------------------------------------------------------
-- 1. sys_region 行政区划表（省/市/区县三级，自关联）
--    需求 NO.1「省表、市表」；NO.14 选择省市或具体网格
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS sys_region;
CREATE TABLE sys_region
(
    pid          BIGINT      NOT NULL AUTO_INCREMENT COMMENT '主键',
    parent_id    BIGINT      NOT NULL DEFAULT 0 COMMENT '上级区划 pid，0=无上级（省级）',
    region_code  VARCHAR(12) NOT NULL COMMENT '行政区划代码',
    region_name  VARCHAR(50) NOT NULL COMMENT '区划名称',
    region_level TINYINT     NOT NULL COMMENT '层级：1=省 2=市 3=区/县',
    short_name   VARCHAR(20)          DEFAULT NULL COMMENT '简称（省级用）',
    sort_no      INT         NOT NULL DEFAULT 0 COMMENT '排序',
    create_time  DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    PRIMARY KEY (pid),
    UNIQUE KEY uk_region_code (region_code),
    KEY idx_region_parent (parent_id),
    KEY idx_region_name (parent_id, region_name)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='行政区划表（省/市/区县自关联）';


-- ---------------------------------------------------------------------------
-- 2. sys_grid 网格表
--    需求 NO.14/15 网格地址选择、NO.28 反馈记录网格、NO.58 网格覆盖率统计
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS sys_grid;
CREATE TABLE sys_grid
(
    gid         BIGINT         NOT NULL AUTO_INCREMENT COMMENT '主键',
    grid_code   VARCHAR(32)    NOT NULL COMMENT '网格编号',
    grid_name   VARCHAR(100)   NOT NULL COMMENT '网格名称',
    region_id   BIGINT         NOT NULL COMMENT '所属区/县 pid（sys_region, region_level=3）',
    province_id BIGINT         NOT NULL COMMENT '冗余-省 pid（sys_region, region_level=1）',
    city_id     BIGINT         NOT NULL COMMENT '冗余-市 pid（sys_region, region_level=2）',
    address     VARCHAR(200)            DEFAULT NULL COMMENT '详细地址',
    longitude   DECIMAL(10, 6)          DEFAULT NULL COMMENT '经度',
    latitude    DECIMAL(10, 6)          DEFAULT NULL COMMENT '纬度',
    status      TINYINT        NOT NULL DEFAULT 1 COMMENT '状态：1=启用 0=停用',
    create_time DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (gid),
    UNIQUE KEY uk_grid_code (grid_code),
    KEY idx_grid_region (region_id),
    KEY idx_grid_province_city (province_id, city_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='网格表';

-- ---------------------------------------------------------------------------
-- 3. sys_user 用户表
--    需求 NO.1「账号信息」「公众监督员信息表」「网格员信息」合并为一张表
--    需求 NO.7 注册输入（姓名、性别、年龄、手机号、密码）
--    需求 NO.13 支持用户名或手机号登录；NO.9 角色标识决定权限
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS sys_user;
CREATE TABLE sys_user
(
    uid             BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    username        VARCHAR(50)  NOT NULL COMMENT '用户名（登录账号）',
    password        VARCHAR(100) NOT NULL COMMENT '密码（建议存 BCrypt 哈希，勿存明文）',
    phone           VARCHAR(20)  NOT NULL COMMENT '手机号（亦可作为登录账号）',
    role_code       VARCHAR(32)  NOT NULL COMMENT '角色标识：SUPERVISOR=公众监督员 GRID_MANAGER=网格员 ADMIN=系统管理员 DECISION_MAKER=决策者',
    real_name       VARCHAR(50)           DEFAULT NULL COMMENT '姓名',
    gender          TINYINT               DEFAULT NULL COMMENT '性别：1=男 2=女',
    age             INT                   DEFAULT NULL COMMENT '年龄',
    grid_id         BIGINT                DEFAULT NULL COMMENT '负责的网格 gid（sys_grid，仅网格员使用）',
    work_no         VARCHAR(32)           DEFAULT NULL COMMENT '工号（仅网格员使用）',
    status          TINYINT      NOT NULL DEFAULT 1 COMMENT '状态：1=正常 0=禁用',
    last_login_time DATETIME              DEFAULT NULL COMMENT '最近登录时间',
    create_time     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (uid),
    UNIQUE KEY uk_user_username (username),
    UNIQUE KEY uk_user_phone (phone),
    KEY idx_user_role (role_code),
    KEY idx_user_grid (grid_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='用户表（账号与角色合一）';


-- ---------------------------------------------------------------------------
-- 4. aqi_level 空气质量指数等级表
--    需求 NO.1「空气质量指数分类」；NO.27 公众预估等级；NO.38 实测自动判定
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS aqi_level;
CREATE TABLE aqi_level
(
    lid         BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    level_no    TINYINT      NOT NULL COMMENT '等级序号 1~6',
    level_name  VARCHAR(20)  NOT NULL COMMENT '等级名称',
    aqi_min     INT          NOT NULL COMMENT 'AQI 下限',
    aqi_max     INT          NOT NULL COMMENT 'AQI 上限（严重污染按 500 计）',
    is_exceed   TINYINT      NOT NULL DEFAULT 0 COMMENT '是否计入超标：1=是 0=否',
    color       VARCHAR(20)           DEFAULT NULL COMMENT '大屏配色（十六进制）',
    description VARCHAR(200)          DEFAULT NULL COMMENT '健康影响说明',
    PRIMARY KEY (lid),
    UNIQUE KEY uk_aqi_level_no (level_no)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='空气质量指数等级表';

-- ---------------------------------------------------------------------------
-- 5. feedback_order 公众反馈工单表
--    需求 NO.28 上报（记录等级/网格/用户/时间，初始「待指派」）
--    需求 NO.30/33 网格员按 assignee_id 查自己的任务
--    需求 NO.42/43 管理端按省市、状态、时间范围过滤分页
--    需求 NO.48 指派（更新 assignee_id）并由 oper_log 记录可追溯
--    需求 NO.38 核查后状态变「已核查」
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS feedback_order;
CREATE TABLE feedback_order
(
    oid                BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    order_no           VARCHAR(32)  NOT NULL COMMENT '工单编号',
    reporter_id        BIGINT       NOT NULL COMMENT '上报人 uid（sys_user）',
    grid_id            BIGINT       NOT NULL COMMENT '网格 gid（sys_grid）',
    province_id        BIGINT       NOT NULL COMMENT '冗余-省 pid（sys_region）',
    city_id            BIGINT       NOT NULL COMMENT '冗余-市 pid（sys_region）',
    estimated_level_id BIGINT       NOT NULL COMMENT '公众预估等级 lid（aqi_level）',
    feedback_content   VARCHAR(500)          DEFAULT NULL COMMENT '反馈信息',
    feedback_time      DATETIME     NOT NULL COMMENT '反馈时间',
    status             VARCHAR(20)  NOT NULL DEFAULT 'PENDING_ASSIGN' COMMENT '状态：PENDING_ASSIGN=待指派 ASSIGNED=已指派 CHECKED=已核查',
    assignee_id        BIGINT                DEFAULT NULL COMMENT '当前负责网格员 uid（sys_user）',
    assign_time        DATETIME              DEFAULT NULL COMMENT '最近一次指派时间',
    check_time         DATETIME              DEFAULT NULL COMMENT '核查完成时间',
    create_time        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time        DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (oid),
    UNIQUE KEY uk_order_no (order_no),
    KEY idx_order_status_time (status, feedback_time),
    KEY idx_order_reporter (reporter_id),
    KEY idx_order_grid (grid_id),
    KEY idx_order_assignee (assignee_id),
    KEY idx_order_province_city (province_id, city_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='公众反馈工单表';


-- ---------------------------------------------------------------------------
-- 6. aqi_measure AQI 实测数据表
--    需求 NO.37/38 网格员录入 SO2/CO/PM2.5，系统自动判定实测等级
--    需求 NO.16「同一工单不可重复提交实测数据」→ order_id 唯一键
--    需求 NO.50/54 管理端按省市、确认日期筛选
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS aqi_measure;
CREATE TABLE aqi_measure
(
    mid               BIGINT         NOT NULL AUTO_INCREMENT COMMENT '主键',
    order_id          BIGINT         NOT NULL COMMENT '关联工单 oid（feedback_order）',
    province_id       BIGINT         NOT NULL COMMENT '冗余-省 pid（统计用）',
    city_id           BIGINT         NOT NULL COMMENT '冗余-市 pid（统计用）',
    so2               DECIMAL(10, 2)          DEFAULT NULL COMMENT 'SO2 浓度（ug/m³）',
    co                DECIMAL(10, 2)          DEFAULT NULL COMMENT 'CO 浓度（ug/m³）',
    pm25              DECIMAL(10, 2)          DEFAULT NULL COMMENT 'PM2.5 浓度（ug/m³）',
    measured_level_id BIGINT         NOT NULL COMMENT '实测等级 lid（aqi_level）',
    grid_manager_id   BIGINT         NOT NULL COMMENT '录入网格员 uid（sys_user）',
    confirm_date      DATE           NOT NULL COMMENT '确认日期（列表筛选用）',
    confirm_time      DATETIME       NOT NULL COMMENT '确认时间',
    remark            VARCHAR(200)            DEFAULT NULL COMMENT '备注',
    create_time       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    update_time       DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (mid),
    UNIQUE KEY uk_measure_order (order_id),
    KEY idx_measure_confirm_date (confirm_date),
    KEY idx_measure_province_city (province_id, city_id),
    KEY idx_measure_manager (grid_manager_id)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='AQI 实测数据表';

-- ---------------------------------------------------------------------------
-- 7. aqi_statistics 统计数据表（统计明细与指标卡片合一）
--    需求 NO.55/58 统计结果存入统计表供大屏调用：
--      AQI_LEVEL_DIST   AQI 等级分布
--      PROVINCE_EXCEED  各省污染物超标数量
--      MONTH_TREND      12 个月超标趋势
--      GRID_COVERAGE    网格覆盖率
--      POLLUTANT_EXCEED 分污染物超标数量
--      SUMMARY          大屏顶部指标卡片（用 metric_key 区分具体指标）
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS aqi_statistics;
CREATE TABLE aqi_statistics
(
    stid           BIGINT         NOT NULL AUTO_INCREMENT COMMENT '主键',
    stat_type      VARCHAR(30)    NOT NULL COMMENT '统计类型：AQI_LEVEL_DIST/PROVINCE_EXCEED/MONTH_TREND/GRID_COVERAGE/POLLUTANT_EXCEED/SUMMARY',
    stat_dimension VARCHAR(20)    NOT NULL DEFAULT 'ALL' COMMENT '统计维度：ALL/PROVINCE/CITY/GRID/MONTH/DAY',
    dimension_id   BIGINT         NOT NULL DEFAULT 0 COMMENT '维度对象 id（省/市/网格 pid，无则 0）',
    dimension_name VARCHAR(100)   NOT NULL DEFAULT '' COMMENT '维度对象名称（省名/月名等）',
    stat_period    VARCHAR(20)    NOT NULL DEFAULT '' COMMENT '统计周期，如 2026-10',
    aqi_level_id   BIGINT         NOT NULL DEFAULT 0 COMMENT '等级 lid（等级分布用，无则 0）',
    pollutant      VARCHAR(10)    NOT NULL DEFAULT '' COMMENT '污染物：PM25/SO2/CO（无则空串）',
    metric_key     VARCHAR(50)    NOT NULL DEFAULT '' COMMENT '指标标识（SUMMARY 用：MEASURE_TOTAL/POLLUTION_COUNT/IMPROVEMENT_COUNT/GRID_TOTAL/GRID_COVERED/GRID_COVERAGE）',
    metric_value   DECIMAL(14, 2) NOT NULL DEFAULT 0 COMMENT '指标值（数量或百分比）',
    create_time    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '生成时间',
    PRIMARY KEY (stid),
    UNIQUE KEY uk_stat (stat_type, stat_dimension, stat_period, dimension_id, aqi_level_id, pollutant, metric_key),
    KEY idx_stat_type_period (stat_type, stat_period)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='统计数据表（供大屏调用）';


-- ---------------------------------------------------------------------------
-- 8. oper_log 操作日志表
--    需求 NO.45/48「记录操作日志用于追溯」→ 兼任指派历史
--    需求 NO.22 管理员查看登录时段及操作记录
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS oper_log;
CREATE TABLE oper_log
(
    opid          BIGINT       NOT NULL AUTO_INCREMENT COMMENT '主键',
    user_id       BIGINT                DEFAULT NULL COMMENT '操作人 uid（sys_user）',
    username      VARCHAR(50)           DEFAULT NULL COMMENT '操作人用户名（冗余便于展示）',
    module        VARCHAR(50)           DEFAULT NULL COMMENT '模块，如 反馈工单/指派/登录',
    operation     VARCHAR(100)          DEFAULT NULL COMMENT '操作描述，如「指派工单」',
    method        VARCHAR(200)          DEFAULT NULL COMMENT '请求接口',
    request_param TEXT                  COMMENT '请求参数',
    order_id      BIGINT                DEFAULT NULL COMMENT '关联工单 oid（按工单追溯）',
    ip            VARCHAR(64)           DEFAULT NULL COMMENT '操作 IP',
    status        TINYINT      NOT NULL DEFAULT 1 COMMENT '结果：1=成功 0=失败',
    error_msg     VARCHAR(500)          DEFAULT NULL COMMENT '失败原因',
    oper_time     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '操作时间',
    PRIMARY KEY (opid),
    KEY idx_log_order (order_id),
    KEY idx_log_user (user_id),
    KEY idx_log_time (oper_time)
) ENGINE = InnoDB
  DEFAULT CHARSET = utf8mb4
  COLLATE = utf8mb4_general_ci COMMENT ='操作日志表';

-- ---------------------------------------------------------------------------
-- 字典数据：空气质量指数等级（6 级）
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO aqi_level (lid, level_no, level_name, aqi_min, aqi_max, is_exceed, color, description)
VALUES (1, 1, '优', 0, 50, 0, '#00E400', '空气质量令人满意，基本无空气污染'),
       (2, 2, '良', 51, 100, 0, '#FFFF00', '除少数敏感人群外可正常活动'),
       (3, 3, '轻度污染', 101, 150, 1, '#FF7E00', '敏感人群症状有轻度加剧，健康人群出现刺激症状'),
       (4, 4, '中度污染', 151, 200, 1, '#FF0000', '敏感人群症状明显加剧，可能影响健康人群心脏、呼吸系统'),
       (5, 5, '重度污染', 201, 300, 1, '#8F3F97', '健康人群普遍出现症状，敏感人群症状显著加剧'),
       (6, 6, '严重污染', 301, 500, 1, '#7E0023', '健康人群运动耐受力降低，有明显强烈症状');


-- ---------------------------------------------------------------------------
-- 字典数据：省级行政区（34 个，parent_id=0 表示省级）
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO sys_region (pid, parent_id, region_code, region_name, region_level, short_name, sort_no)
VALUES (1, 0, '110000', '北京市', 1, '京', 1),
       (2, 0, '120000', '天津市', 1, '津', 2),
       (3, 0, '130000', '河北省', 1, '冀', 3),
       (4, 0, '140000', '山西省', 1, '晋', 4),
       (5, 0, '150000', '内蒙古自治区', 1, '蒙', 5),
       (6, 0, '210000', '辽宁省', 1, '辽', 6),
       (7, 0, '220000', '吉林省', 1, '吉', 7),
       (8, 0, '230000', '黑龙江省', 1, '黑', 8),
       (9, 0, '310000', '上海市', 1, '沪', 9),
       (10, 0, '320000', '江苏省', 1, '苏', 10),
       (11, 0, '330000', '浙江省', 1, '浙', 11),
       (12, 0, '340000', '安徽省', 1, '皖', 12),
       (13, 0, '350000', '福建省', 1, '闽', 13),
       (14, 0, '360000', '江西省', 1, '赣', 14),
       (15, 0, '370000', '山东省', 1, '鲁', 15),
       (16, 0, '410000', '河南省', 1, '豫', 16),
       (17, 0, '420000', '湖北省', 1, '鄂', 17),
       (18, 0, '430000', '湖南省', 1, '湘', 18),
       (19, 0, '440000', '广东省', 1, '粤', 19),
       (20, 0, '450000', '广西壮族自治区', 1, '桂', 20),
       (21, 0, '460000', '海南省', 1, '琼', 21),
       (22, 0, '500000', '重庆市', 1, '渝', 22),
       (23, 0, '510000', '四川省', 1, '川', 23),
       (24, 0, '520000', '贵州省', 1, '黔', 24),
       (25, 0, '530000', '云南省', 1, '滇', 25),
       (26, 0, '540000', '西藏自治区', 1, '藏', 26),
       (27, 0, '610000', '陕西省', 1, '陕', 27),
       (28, 0, '620000', '甘肃省', 1, '甘', 28),
       (29, 0, '630000', '青海省', 1, '青', 29),
       (30, 0, '640000', '宁夏回族自治区', 1, '宁', 30),
       (31, 0, '650000', '新疆维吾尔自治区', 1, '新', 31),
       (32, 0, '710000', '台湾省', 1, '台', 32),
       (33, 0, '810000', '香港特别行政区', 1, '港', 33),
       (34, 0, '820000', '澳门特别行政区', 1, '澳', 34);

-- ---------------------------------------------------------------------------
-- 字典数据：城市（示例 30 个，pid 从 101 起；parent_id 指向省级 pid）
-- 说明：完整的全国城市/区县数据需从民政部行政区划数据导入后追加
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO sys_region (pid, parent_id, region_code, region_name, region_level, sort_no)
VALUES (101, 6, '210100', '沈阳市', 2, 1),
       (102, 6, '210200', '大连市', 2, 2),
       (103, 6, '210300', '鞍山市', 2, 3),
       (104, 6, '210400', '抚顺市', 2, 4),
       (105, 6, '210500', '本溪市', 2, 5),
       (106, 6, '210600', '丹东市', 2, 6),
       (107, 6, '210700', '锦州市', 2, 7),
       (108, 6, '210800', '营口市', 2, 8),
       (109, 6, '210900', '阜新市', 2, 9),
       (110, 6, '211000', '辽阳市', 2, 10),
       (111, 6, '211100', '盘锦市', 2, 11),
       (112, 6, '211200', '铁岭市', 2, 12),
       (113, 6, '211300', '朝阳市', 2, 13),
       (114, 6, '211400', '葫芦岛市', 2, 14),
       (115, 1, '110100', '北京市', 2, 1),
       (116, 2, '120100', '天津市', 2, 1),
       (117, 9, '310100', '上海市', 2, 1),
       (118, 22, '500100', '重庆市', 2, 1),
       (119, 19, '440100', '广州市', 2, 1),
       (120, 19, '440300', '深圳市', 2, 2),
       (121, 10, '320100', '南京市', 2, 1),
       (122, 10, '320500', '苏州市', 2, 2),
       (123, 11, '330100', '杭州市', 2, 1),
       (124, 11, '330200', '宁波市', 2, 2),
       (125, 15, '370100', '济南市', 2, 1),
       (126, 15, '370200', '青岛市', 2, 2),
       (127, 23, '510100', '成都市', 2, 1),
       (128, 17, '420100', '武汉市', 2, 1),
       (129, 27, '610100', '西安市', 2, 1),
       (130, 16, '410100', '郑州市', 2, 1);


-- ---------------------------------------------------------------------------
-- 字典数据：区/县（12 个，pid 从 201 起；与演示网格一一对应）
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO sys_region (pid, parent_id, region_code, region_name, region_level, sort_no)
VALUES (201, 102, '210202', '中山区', 3, 1),
       (202, 102, '210203', '西岗区', 3, 2),
       (203, 102, '210204', '沙河口区', 3, 3),
       (204, 102, '210211', '甘井子区', 3, 4),
       (205, 102, '210213', '金州区', 3, 5),
       (206, 115, '110105', '朝阳区', 3, 1),
       (207, 117, '310115', '浦东新区', 3, 1),
       (208, 119, '440106', '天河区', 3, 1),
       (209, 120, '440305', '南山区', 3, 1),
       (210, 125, '370102', '历下区', 3, 1),
       (211, 121, '320106', '鼓楼区', 3, 1),
       (212, 123, '330106', '西湖区', 3, 1);


-- ---------------------------------------------------------------------------
-- 字典数据：网格（12 个，region_id 指向区/县，province_id/city_id 冗余）
-- ---------------------------------------------------------------------------
INSERT IGNORE INTO sys_grid (gid, grid_code, grid_name, region_id, province_id, city_id, address, longitude, latitude, status)
VALUES (1, 'GRID-DL-001', '大连市中山区人民路网格', 201, 6, 102, '辽宁省大连市中山区人民路', 121.639000, 38.918000, 1),
       (2, 'GRID-DL-002', '大连市西岗区香炉礁网格', 202, 6, 102, '辽宁省大连市西岗区香炉礁街道', 121.604000, 38.928000, 1),
       (3, 'GRID-DL-003', '大连市沙河口区星海广场网格', 203, 6, 102, '辽宁省大连市沙河口区星海广场', 121.587000, 38.880000, 1),
       (4, 'GRID-DL-004', '大连市甘井子区周水子网格', 204, 6, 102, '辽宁省大连市甘井子区周水子街道', 121.566000, 38.953000, 1),
       (5, 'GRID-DL-005', '大连市金州区开发区网格', 205, 6, 102, '辽宁省大连市金州区经济技术开发区', 121.783000, 39.050000, 1),
       (6, 'GRID-BJ-001', '北京市朝阳区CBD网格', 206, 1, 115, '北京市朝阳区国贸商圈', 116.461000, 39.909000, 1),
       (7, 'GRID-SH-001', '上海市浦东新区陆家嘴网格', 207, 9, 117, '上海市浦东新区陆家嘴金融城', 121.506000, 31.245000, 1),
       (8, 'GRID-GZ-001', '广州市天河区珠江新城网格', 208, 19, 119, '广东省广州市天河区珠江新城', 113.324000, 23.120000, 1),
       (9, 'GRID-SZ-001', '深圳市南山区科技园网格', 209, 19, 120, '广东省深圳市南山区科技园', 113.945000, 22.535000, 1),
       (10, 'GRID-JN-001', '济南市历下区泉城路网格', 210, 15, 125, '山东省济南市历下区泉城路', 117.024000, 36.671000, 1),
       (11, 'GRID-NJ-001', '南京市鼓楼区新街口网格', 211, 10, 121, '江苏省南京市鼓楼区新街口', 118.778000, 32.043000, 1),
       (12, 'GRID-HZ-001', '杭州市西湖区武林广场网格', 212, 11, 123, '浙江省杭州市西湖区武林广场', 120.163000, 30.276000, 1);


SET FOREIGN_KEY_CHECKS = 1;