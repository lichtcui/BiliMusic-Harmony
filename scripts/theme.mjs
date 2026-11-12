// 颜色真源生成器与防回归守卫（零依赖纯 Node ESM）。
//
//   node scripts/theme.mjs --write   由 scripts/palette.json 生成两份 color.json
//   node scripts/theme.mjs --check   校验生成物与七条规则（0–6），失败以非零退出码表达
//
// 规范：单一真源 + 守卫规则；改动流程见 AGENTS.md「构建与验证」。
// 扫描根必须钉死为 entry/src/main/ets：构建输出里可能存在源码副本，
// 浅根 glob 会产出幻影命中。

import fs from 'node:fs'
import path from 'node:path'
import { projectRoot } from './harmony-tools.mjs'

const usage = 'node scripts/theme.mjs --write | --check'

const PALETTE_PATH = path.join(projectRoot, 'scripts', 'palette.json')
const ETS_SOURCE_ROOT = path.join(projectRoot, 'entry', 'src', 'main', 'ets')
const FACADE_PATH = path.join(ETS_SOURCE_ROOT, 'theme', 'NativeTheme.ets')
const RESOURCE_TARGETS = [
  {
    mode: 'light',
    label: 'base',
    file: path.join(projectRoot, 'entry', 'src', 'main', 'resources', 'base', 'element', 'color.json'),
  },
  {
    mode: 'dark',
    label: 'dark',
    file: path.join(projectRoot, 'entry', 'src', 'main', 'resources', 'dark', 'element', 'color.json'),
  },
]

const ARGB_PATTERN = /^#[0-9A-Fa-f]{8}$/
const SEMANTIC_KEY_PATTERN = /^native_[a-z0-9_]+$/
const COLOR_WORD_PATTERN = /(cream|gold|olive|sage|mint|khaki|red|blue|green)/
const START_WINDOW_KEY = 'start_window_background'
const PALETTE_EXTRA_KEYS = new Set(['comment'])
const FACADE_DECLARATION =
  /static\s+readonly\s+([A-Za-z_$][\w$]*)\s*:\s*Resource\s*=\s*\$r\(\s*'app\.color\.([a-z0-9_]+)'\s*\)/
const COLOR_RESOURCE_REFERENCE = /app\.color\.([a-z0-9_]+)/
const THEME_COLORS_USAGE = /ThemeColors\.([A-Za-z_$][\w$]*)/g
const LITERAL_COLOR = /#(?:[0-9A-Fa-f]{8}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{4}|[0-9A-Fa-f]{3})\b/g
const HEX_NUMBER_COLOR =
  /\b(?:Color|color|fontColor|backgroundColor|borderColor|shadowColor|fillColor|strokeColor|tintColor|placeholderColor|caretColor|selectedColor|trackColor|blockColor)\s*\(\s*0[xX][0-9A-Fa-f]{6,8}\b/g
const NAMED_COLOR =
  /Color\.(White|Black|Gray|Grey|Red|Green|Blue|Yellow|Orange|Pink|Brown|Cyan|Magenta|Purple)\b/g
const FUNCTION_COLOR = /\brgba?\s*\(/g

// 规则 6 的被禁角色（重命名之后的字段名）：这些角色描述"面/底/线"，
// 不该出现在 fontColor 里。onAccent / onAccentAction / iconInactive / iconOnInset 是正确的文字色。
const BANNED_FONT_ROLES = [
  'bg',
  'surface',
  'surfaceInset',
  'accentSoft',
  'accentAction',
  'line',
  'progressTrack',
  'scrim',
]

// 规则 4 白名单：临时豁免，不是永久通行证。每条都要写清移除条件，且必须命中预期内容，
// 否则视为"行号漂移"报错（行号以上任何插入都会让 file:line 失配）。
// 2026-11 起为空：二维码前景/背景已从 `Color.Black`/`Color.White` 收进
// `native_qr_ink` / `native_qr_paper`（两套主题取同一组 primitive，值不变），
// 那份"永久白名单"不再需要；仓库里目前没有其它合法字面色。
const LITERAL_WHITELIST = []

function relative(filePath) {
  return path.relative(projectRoot, filePath).split(path.sep).join('/')
}

function describe(error) {
  return error instanceof Error ? error.message : String(error)
}

function isPlainObject(value) {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function readText(filePath) {
  return fs.readFileSync(filePath, 'utf8')
}

function listEtsFiles(directory) {
  const files = []
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const entryPath = path.join(directory, entry.name)
    if (entry.isDirectory()) {
      files.push(...listEtsFiles(entryPath))
    } else if (entry.isFile() && entry.name.endsWith('.ets')) {
      files.push(entryPath)
    }
  }
  return files.sort()
}

function loadPalette() {
  if (!fs.existsSync(PALETTE_PATH)) {
    throw new Error(`缺少调色板真源: ${relative(PALETTE_PATH)}`)
  }

  let raw
  try {
    raw = JSON.parse(readText(PALETTE_PATH))
  } catch (error) {
    throw new Error(`无法解析 ${relative(PALETTE_PATH)}: ${describe(error)}`)
  }

  if (!isPlainObject(raw)) {
    throw new Error(`${relative(PALETTE_PATH)} 顶层必须是对象`)
  }
  for (const key of Object.keys(raw)) {
    if (!['primitives', 'semantic'].includes(key) && !PALETTE_EXTRA_KEYS.has(key)) {
      throw new Error(`${relative(PALETTE_PATH)} 出现未知字段: ${key}`)
    }
  }

  const primitives = raw.primitives
  if (!isPlainObject(primitives) || Object.keys(primitives).length === 0) {
    throw new Error(`${relative(PALETTE_PATH)} 缺少非空的 primitives`)
  }
  for (const [name, value] of Object.entries(primitives)) {
    if (typeof value !== 'string' || !ARGB_PATTERN.test(value)) {
      throw new Error(`primitive ${name} 的值必须是 8 位 ARGB（#AARRGGBB），实际: ${String(value)}`)
    }
  }

  const semantic = raw.semantic
  if (!isPlainObject(semantic) || Object.keys(semantic).length === 0) {
    throw new Error(`${relative(PALETTE_PATH)} 缺少非空的 semantic`)
  }

  const entries = []
  for (const [name, definition] of Object.entries(semantic)) {
    if (!isPlainObject(definition)) {
      throw new Error(`semantic ${name} 必须是 { light, dark } 对象`)
    }
    for (const mode of Object.keys(definition)) {
      if (mode !== 'light' && mode !== 'dark') {
        throw new Error(`semantic ${name} 出现未知字段: ${mode}`)
      }
    }
    for (const mode of ['light', 'dark']) {
      if (!(mode in definition)) {
        throw new Error(`semantic ${name} 缺少 ${mode} 取值（dark 是覆盖层，缺键会静默回落 base）`)
      }
    }
    entries.push({
      name,
      light: resolveValue(name, 'light', definition.light, primitives),
      dark: resolveValue(name, 'dark', definition.dark, primitives),
    })
  }

  if (!entries.some((entry) => entry.name === START_WINDOW_KEY)) {
    throw new Error(`semantic 缺少 ${START_WINDOW_KEY}（module.json5 的 startWindowBackground 依赖它）`)
  }

  return entries
}

function resolveValue(key, mode, value, primitives) {
  if (typeof value !== 'string' || value.length === 0) {
    throw new Error(`semantic ${key} 的 ${mode} 必须是 primitive 名或字面 8 位 ARGB`)
  }
  if (value.startsWith('#')) {
    if (!ARGB_PATTERN.test(value)) {
      throw new Error(`semantic ${key} 的 ${mode} 字面值必须是 8 位 ARGB（#AARRGGBB），实际: ${value}`)
    }
    return value
  }
  if (!(value in primitives)) {
    throw new Error(`semantic ${key} 的 ${mode} 引用了不存在的 primitive: ${value}`)
  }
  return primitives[value]
}

function renderColorJson(entries, mode) {
  const color = entries.map((entry) => ({ name: entry.name, value: entry[mode] }))
  return `${JSON.stringify({ color }, null, 2)}\n`
}

function readResourceEntries(filePath) {
  if (!fs.existsSync(filePath)) return null
  let raw
  try {
    raw = JSON.parse(readText(filePath))
  } catch {
    return null
  }
  if (!isPlainObject(raw) || !Array.isArray(raw.color)) return null
  const entries = []
  for (const item of raw.color) {
    if (!isPlainObject(item) || typeof item.name !== 'string' || typeof item.value !== 'string') {
      return null
    }
    entries.push({ name: item.name, value: item.value })
  }
  return entries
}

function toCamelCase(key) {
  return key
    .replace(/^native_/, '')
    .replace(/_([a-z0-9])/g, (_match, letter) => letter.toUpperCase())
}

function escapeRegExp(text) {
  return text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function lineOf(text, index) {
  return text.slice(0, index).split('\n').length
}

// 返回从 '(' 开始、与之配对的 ')' 下标；找不到（跨行/截断）返回 -1。
function matchBalanced(text, openIndex) {
  let depth = 0
  for (let index = openIndex; index < text.length; index += 1) {
    const char = text[index]
    if (char === '(' || char === '[') depth += 1
    else if (char === ')' || char === ']') {
      depth -= 1
      if (depth === 0) return index
      if (depth < 0) return -1
    }
  }
  return -1
}

function findCalls(text, callee) {
  const calls = []
  const needle = `${callee}(`
  let index = text.indexOf(needle)
  while (index !== -1) {
    const before = text[index - 1]
    const isIdentifier = before !== undefined && /[\w$]/.test(before)
    if (!isIdentifier) {
      const openIndex = index + needle.length - 1
      const closeIndex = matchBalanced(text, openIndex)
      if (closeIndex !== -1) {
        calls.push({ index, text: text.slice(openIndex, closeIndex + 1) })
      }
    }
    index = text.indexOf(needle, index + needle.length)
  }
  return calls
}

function parseArgs(argv) {
  const unknown = argv.filter((argument) => argument !== '--write' && argument !== '--check')
  if (unknown.length > 0) {
    throw new Error(`未知选项: ${unknown[0]}`)
  }
  const selected = argv.filter((argument) => argument === '--write' || argument === '--check')
  if (selected.length !== 1) {
    throw new Error('必须且只能指定 --write 或 --check 之一')
  }
  return selected[0]
}

function writeResources(entries) {
  for (const target of RESOURCE_TARGETS) {
    fs.mkdirSync(path.dirname(target.file), { recursive: true })
    const content = renderColorJson(entries, target.mode)
    fs.writeFileSync(target.file, content)
    const written = readText(target.file)
    if (written !== content) {
      throw new Error(`写入后校验失败: ${relative(target.file)}`)
    }
    console.log(`已生成: ${relative(target.file)} (${entries.length} 键, ${target.label})`)
  }
  console.log('提示: 资源文件是生成物，请勿手工修改；校验用 node scripts/theme.mjs --check')
}

function checkGenerated(entries) {
  const problems = []
  const expectedByMode = new Map(
    RESOURCE_TARGETS.map((target) => [
      target.mode,
      new Map(entries.map((entry) => [entry.name, entry[target.mode]])),
    ]),
  )

  for (const target of RESOURCE_TARGETS) {
    if (!fs.existsSync(target.file)) {
      problems.push(`生成物缺失: ${relative(target.file)}（运行 --write）`)
      continue
    }
    const actualText = readText(target.file)
    const expectedText = renderColorJson(entries, target.mode)
    if (actualText === expectedText) continue

    const actualEntries = readResourceEntries(target.file)
    if (!actualEntries) {
      problems.push(`${relative(target.file)} 与真源不一致，且无法解析为 color.json 结构`)
      continue
    }
    const expected = expectedByMode.get(target.mode)
    const details = []
    for (const entry of actualEntries) {
      if (!expected.has(entry.name)) {
        details.push(`多出键 ${entry.name}`)
      } else if (expected.get(entry.name) !== entry.value) {
        details.push(`${entry.name}: 磁盘 ${entry.value} ≠ 真源 ${expected.get(entry.name)}`)
      }
    }
    for (const entry of entries) {
      if (!actualEntries.some((item) => item.name === entry.name)) {
        details.push(`缺少键 ${entry.name}`)
      }
    }
    problems.push(
      `${relative(target.file)} 与真源不一致（${details.length > 0 ? details.slice(0, 5).join('; ') : '仅格式/键顺序差异'}）`,
    )
  }
  return problems
}

function checkKeySets() {
  const problems = []
  const loaded = RESOURCE_TARGETS.map((target) => ({
    target,
    entries: readResourceEntries(target.file),
  }))
  for (const item of loaded) {
    if (!item.entries) {
      problems.push(`无法读取 ${relative(item.target.file)} 的键集合（文件缺失或不是合法 color.json）`)
    }
  }
  if (problems.length > 0) return problems

  const [base, dark] = loaded
  const baseNames = base.entries.map((entry) => entry.name)
  const darkNames = dark.entries.map((entry) => entry.name)
  const darkSet = new Set(darkNames)
  const baseSet = new Set(baseNames)
  for (const name of baseNames) {
    if (!darkSet.has(name)) problems.push(`${dark.target.label} 缺少键 ${name}（会静默回落 base）`)
  }
  for (const name of darkNames) {
    if (!baseSet.has(name)) problems.push(`${dark.target.label} 多出键 ${name}（base 里不存在）`)
  }
  return problems
}

function checkValueSyntax() {
  const problems = []
  for (const target of RESOURCE_TARGETS) {
    const entries = readResourceEntries(target.file)
    if (!entries) {
      problems.push(`无法读取 ${relative(target.file)} 进行取值校验`)
      continue
    }
    for (const entry of entries) {
      if (!ARGB_PATTERN.test(entry.value)) {
        problems.push(`${relative(target.file)} 的 ${entry.name} 不是 8 位 ARGB: ${entry.value}`)
      }
    }
  }
  return problems
}

function collectEtsScan() {
  const files = listEtsFiles(ETS_SOURCE_ROOT)
  const facadeLines = []
  const usages = []
  const resourceReferences = []
  const data = []

  for (const file of files) {
    const text = readText(file)
    data.push({ file, text })
    if (file === FACADE_PATH) {
      text.split('\n').forEach((line, offset) => {
        const match = FACADE_DECLARATION.exec(line)
        if (match) {
          facadeLines.push({ field: match[1], key: match[2], line: offset + 1 })
        }
      })
    } else {
      const referencePattern = new RegExp(COLOR_RESOURCE_REFERENCE, 'g')
      let reference = referencePattern.exec(text)
      while (reference) {
        resourceReferences.push({ file, line: lineOf(text, reference.index), key: reference[1] })
        reference = referencePattern.exec(text)
      }
    }
    const usagePattern = new RegExp(THEME_COLORS_USAGE, 'g')
    let usage = usagePattern.exec(text)
    while (usage) {
      usages.push({ file, line: lineOf(text, usage.index), field: usage[1] })
      usage = usagePattern.exec(text)
    }
  }

  return { files, data, facadeLines, usages, resourceReferences }
}

function checkClosure(scan) {
  const problems = []
  const base = readResourceEntries(RESOURCE_TARGETS[0].file)
  if (!base) {
    problems.push('无法读取 base color.json，跳过双向闭环校验')
    return problems
  }

  const resourceKeys = base.map((entry) => entry.name)
  const resourceKeySet = new Set(resourceKeys)
  const declaredByKey = new Map(scan.facadeLines.map((item) => [item.key, item]))
  const declaredFields = new Set(scan.facadeLines.map((item) => item.field))
  const facadePath = relative(FACADE_PATH)

  for (const item of scan.facadeLines) {
    if (!resourceKeySet.has(item.key)) {
      problems.push(`${facadePath}:${item.line} 引用了不存在的资源键 ${item.key}`)
    }
  }
  for (const key of resourceKeys) {
    if (!declaredByKey.has(key) && key !== START_WINDOW_KEY) {
      problems.push(`资源键 ${key} 没有任何 ThemeColors 字段引用它（规则 3 例外只允许 ${START_WINDOW_KEY}）`)
    }
  }

  const usageCounts = new Map()
  for (const usage of scan.usages) {
    if (!declaredFields.has(usage.field)) {
      problems.push(`${relative(usage.file)}:${usage.line} 使用了未声明的字段 ThemeColors.${usage.field}`)
      continue
    }
    usageCounts.set(usage.field, (usageCounts.get(usage.field) ?? 0) + 1)
  }

  for (const item of scan.facadeLines) {
    if (item.key === START_WINDOW_KEY) continue
    if ((usageCounts.get(item.field) ?? 0) === 0) {
      problems.push(`死键 ${item.key}：ThemeColors.${item.field} 声明了但零引用`)
    }
  }

  for (const reference of scan.resourceReferences) {
    problems.push(
      `${relative(reference.file)}:${reference.line} 直接引用了资源 app.color.${reference.key}（应经 ThemeColors 门面）`,
    )
  }

  return problems
}

function checkNaming(scan) {
  const problems = []
  const base = readResourceEntries(RESOURCE_TARGETS[0].file)
  if (!base) {
    problems.push('无法读取 base color.json，跳过命名校验')
    return problems
  }

  const keys = base.map((entry) => entry.name)
  if (!keys.includes(START_WINDOW_KEY)) {
    problems.push(`缺少 ${START_WINDOW_KEY}（module.json5 的 startWindowBackground 依赖它）`)
  }
  for (const key of keys) {
    if (key === START_WINDOW_KEY) continue
    if (!SEMANTIC_KEY_PATTERN.test(key)) {
      problems.push(`键名 ${key} 不匹配 ^native_[a-z0-9_]+$`)
    }
    const word = COLOR_WORD_PATTERN.exec(key)
    if (word) {
      problems.push(`键名 ${key} 含颜色词 ${word[1]}（角色词只描述用途）`)
    }
  }

  for (const item of scan.facadeLines) {
    if (item.key === START_WINDOW_KEY) continue
    const expected = toCamelCase(item.key)
    if (item.field !== expected) {
      problems.push(
        `${relative(FACADE_PATH)}:${item.line} 字段名 ${item.field} 与键名 ${item.key} 不对应（应为 ${expected}）`,
      )
    }
  }

  return problems
}

function checkLiteralColors(scan) {
  const problems = []
  const usedWhitelist = new Set()

  for (const { file, text } of scan.data) {
    const relativeFile = relative(file)
    const lines = text.split('\n')
    lines.forEach((line, offset) => {
      const lineNumber = offset + 1
      const hits = []
      const literalPattern = new RegExp(LITERAL_COLOR, 'g')
      let literal = literalPattern.exec(line)
      while (literal) {
        hits.push(literal[0])
        literal = literalPattern.exec(line)
      }
      const namedPattern = new RegExp(NAMED_COLOR, 'g')
      let named = namedPattern.exec(line)
      while (named) {
        hits.push(`Color.${named[1]}`)
        named = namedPattern.exec(line)
      }
      const hexNumberPattern = new RegExp(HEX_NUMBER_COLOR, 'g')
      let hexNumber = hexNumberPattern.exec(line)
      while (hexNumber) {
        hits.push(hexNumber[0])
        hexNumber = hexNumberPattern.exec(line)
      }
      const functionPattern = new RegExp(FUNCTION_COLOR, 'g')
      let functionColor = functionPattern.exec(line)
      while (functionColor) {
        hits.push('rgb()/rgba()')
        functionColor = functionPattern.exec(line)
      }
      if (hits.length === 0) return

      const allowance = LITERAL_WHITELIST.find(
        (item) => item.file === relativeFile && item.line === lineNumber,
      )
      if (!allowance) {
        problems.push(`${relativeFile}:${lineNumber} 出现字面色 ${hits.join(', ')}（白名单外的硬编码）`)
        return
      }
      usedWhitelist.add(allowance)
      if (!allowance.expect.test(line)) {
        problems.push(
          `${relativeFile}:${lineNumber} 命中白名单但内容不符（期望 ${allowance.expect}）——行号可能已漂移，请复核白名单`,
        )
      }
    })
  }

  for (const item of LITERAL_WHITELIST) {
    if (!usedWhitelist.has(item)) {
      problems.push(
        `白名单条目 ${item.file}:${item.line} 未命中任何字面色——行号可能已漂移，请复核（${item.reason}）`,
      )
    }
  }

  return problems
}

function checkFontColorRoles(scan) {
  const problems = []
  for (const { file, text } of scan.data) {
    const relativeFile = relative(file)
    for (const call of findCalls(text, 'fontColor')) {
      for (const role of BANNED_FONT_ROLES) {
        const pattern = new RegExp(`ThemeColors\\.${escapeRegExp(role)}\\b`)
        if (!pattern.test(call.text)) continue
        problems.push(
          `${relativeFile}:${lineOf(text, call.index)} fontColor 里出现被禁角色 ${role}：${call.text.replace(/\s+/g, ' ')}`,
        )
      }
    }
  }
  return problems
}

function runCheck() {
  const entries = loadPalette()
  const scan = collectEtsScan()
  const results = [
    ['规则 0 生成物一致性', checkGenerated(entries)],
    ['规则 1 base/dark 键集合', checkKeySets()],
    ['规则 2 取值合法性', checkValueSyntax()],
    ['规则 3 ThemeColors 与资源双向闭环', checkClosure(scan)],
    ['规则 4 字面色扫描', checkLiteralColors(scan)],
    ['规则 5 角色命名', checkNaming(scan)],
    ['规则 6 fontColor 角色误用', checkFontColorRoles(scan)],
  ]

  let total = 0
  for (const [label, problems] of results) {
    if (problems.length === 0) {
      console.log(`[通过] ${label}`)
      continue
    }
    total += problems.length
    console.log(`[失败] ${label}（${problems.length}）`)
    for (const problem of problems) {
      console.log(`  - ${problem}`)
    }
  }

  console.log(
    `颜色校验: ${entries.length} 键 / 规则 0–6 / ${
      total === 0 ? '全绿' : `${total} 个问题`
    }（扫描 ${scan.files.length} 个 .ets）`,
  )
  if (total > 0) {
    process.exitCode = 1
  }
}

function main() {
  const mode = parseArgs(process.argv.slice(2))
  if (mode === '--write') {
    writeResources(loadPalette())
    return
  }
  runCheck()
}

try {
  main()
} catch (error) {
  console.error(`主题脚本失败: ${describe(error)}`)
  console.error(`用法: ${usage}`)
  process.exitCode = 1
}