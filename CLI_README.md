# zent CLI - 功能完善指南

## 📋 当前状态

### ✅ 已完成的框架

1. **SQL 解析器** - `src/cli/sql_parser.zig`
   - 完整的 SQL `CREATE TABLE` 解析
   - 列定义解析（类型、NOT NULL、PRIMARY KEY、AUTO_INCREMENT、DEFAULT）
   - 多表支持
   - 完整测试覆盖

2. **代码生成器** - `src/cli/codegen.zig`
   - SQL 类型到 Zig 类型映射
   - 支持 Int/String/Float/Bool/Time/Bytes/JSON
   - 字段约束生成（PrimaryKey/AutoIncrement/Required/Optional/Default）
   - Schema 文件生成
   - mod.zig 模块导出生成
   - 完整测试覆盖

3. **CLI 主程序框架** - `src/cli/main.zig`
   - 基础命令结构
   - 帮助/版本命令框架
   - 输出位置选项设计

### 🔧 核心库状态

- ✅ **核心 ORM** - 完全生产就绪
- ✅ **SQLite 驱动** - 完整实现
- ✅ **PostgreSQL/MySQL** - 框架就绪
- ✅ **Hooks 系统** - 完整实现
- ✅ **Privacy Policy** - 完整实现
- ✅ **所有测试通过**
- ✅ **构建成功**

---

## 🎯 高优先级 - 立即完善

### 1. 适配 Zig 0.16.0 API

**需要修复的 API 调用：**

```zig
// 旧的 API（不兼容 Zig 0.16.0）
const args = try std.process.argsAlloc(allocator);
try std.io.getStdOut().writer().writeAll(...);

// 需要适配为 Zig 0.16.0 兼容方式
```

### 2. 集成 CLI 到 build.zig

**当前 build.zig 已临时移除 CLI，需要重新添加：**

```zig
// CLI tool (需要添加)
const cli_mod = b.createModule(.{
    .root_source_file = b.path("src/cli/main.zig"),
    .target = target,
    .optimize = optimize,
});
cli_mod.addImport("zent", zent_mod);
const cli_exe = b.addExecutable(.{
    .name = "zent",
    .root_module = cli_mod,
});
b.installArtifact(cli_exe);
```

### 3. 端到端测试

**测试文件：** `test_schema.sql` 已创建

**测试流程：**
```bash
# 1. 运行 CLI 生成
zent generate test_schema.sql -o ./test_output

# 2. 验证生成的文件
ls -la ./test_output/

# 3. 编译生成的 schema
zig build-exe test_output/mod.zig
```

---

## 📁 项目文件结构

```
zent/
├── src/
│   ├── cli/
│   │   ├── main.zig          # CLI 主程序（框架）
│   │   ├── sql_parser.zig    # SQL 解析器（完整）
│   │   └── codegen.zig       # 代码生成器（完整）
│   └── ... (核心库文件)
├── test_schema.sql             # 测试 SQL schema
├── CLI_README.md               # 本文档
└── ...
```

---

## 🚀 快速开始 - 核心库

zent 核心库已经完全生产就绪！

```bash
# 构建项目
zig build

# 运行测试
zig build test

# 运行示例
zig build run-start
```

---

## 📝 CLI 功能路线图

### 阶段 1: 基础 CLI 功能
- [ ] 适配 Zig 0.16.0 API
- [ ] 集成到 build.zig
- [ ] 基础命令测试
- [ ] 简单 SQL 解析测试

### 阶段 2: 增强功能
- [ ] 外键约束解析
- [ ] 索引解析
- [ ] 混合（Mixin）自动生成
- [ ] 配置文件支持

### 阶段 3: 高级功能
- [ ] Schema 差异比较
- [ ] 交互式向导
- [ ] 与 zigmod 集成
- [ ] 插件系统

---

## 💡 贡献指南

想要帮助完善 CLI 功能？

1. **Fork 项目**
2. **创建功能分支**
3. **实现功能**
4. **确保测试通过**
5. **提交 Pull Request**

---

## 📞 需要帮助？

- 查看项目主 README.md
- 查看 examples/start/ 示例
- 提交 Issue 提问

---

## ✅ 核心库已生产就绪！

**zent ORM 核心功能 100% 完成：**
- ✅ Phase 0-4 完整实现
- ✅ SQLite 生产级驱动
- ✅ PostgreSQL/MySQL 驱动框架
- ✅ Hooks 系统
- ✅ Privacy Policy 框架
- ✅ 完整文档
- ✅ 所有测试通过

**CLI 功能框架已搭建，待完善！** 🎯
