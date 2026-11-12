import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execFileSync } from 'node:child_process'
import { projectRoot } from './harmony-tools.mjs'

const TARGET = 'build-profile.json5'
const DEFAULT_WORKSPACE = path.join(os.homedir(), '.ohos', 'wisp-music-local-signing')
const usage = `用法: npm run signing:apply | npm run signing:restore | npm run signing:status

本机签名差异只保存在仓库外工作区（默认 ${DEFAULT_WORKSPACE}），
可用 WISP_MUSIC_SIGNING_PATCH 指向其他 patch。patch 含凭据，绝不暂存、绝不复制进仓库。`

function patchPath() {
  const candidate = process.env.WISP_MUSIC_SIGNING_PATCH ||
    path.join(DEFAULT_WORKSPACE, 'build-profile-signing.patch')
  const resolved = path.resolve(candidate)
  const relative = path.relative(projectRoot, resolved)
  if (relative === '' || (!relative.startsWith('..') && !path.isAbsolute(relative))) {
    throw new Error(
      `WISP_MUSIC_SIGNING_PATCH 不能指向仓库内路径: ${resolved}；签名 patch 含凭据，只能放在仓库外。`,
    )
  }
  return resolved
}

function git(args) {
  return execFileSync('git', args, { cwd: projectRoot, encoding: 'utf8' }).trim()
}

function gitProbe(args) {
  try {
    execFileSync('git', args, {
      cwd: projectRoot,
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    })
    return true
  } catch {
    return false
  }
}

function worktreeBlob() {
  return git(['hash-object', TARGET])
}

function headBlob() {
  return git(['rev-parse', `HEAD:${TARGET}`])
}

function staged() {
  return git(['diff', '--cached', '--name-only', '--', TARGET])
}

function applyPatch(patch) {
  git(['apply', patch])
  const blob = worktreeBlob()
  if (staged() !== '') {
    throw new Error(`${TARGET} 被暂存了，立刻执行 git restore --staged ${TARGET}`)
  }
  console.log(`已应用 ${patch}`)
  console.log(`${TARGET} blob: ${blob}（未暂存）`)
  console.log('真机构建后执行 npm run signing:restore；提交前 git status --short 不应出现该文件。')
}

function restoreTarget() {
  const before = worktreeBlob()
  const expected = headBlob()
  if (before === expected) {
    console.log(`${TARGET} 已是仓库版本，无需还原。`)
    return
  }
  git(['checkout', '--', TARGET])
  const after = worktreeBlob()
  if (after !== expected) {
    throw new Error(`还原后 blob 与 HEAD 不一致: ${after} != ${expected}`)
  }
  console.log(`已还原 ${TARGET}: ${before} -> ${after}`)
  if (staged() !== '') {
    throw new Error(`${TARGET} 仍在暂存区，执行 git restore --staged ${TARGET}`)
  }
}

function printStatus(patch) {
  const exists = fs.existsSync(patch)
  const current = worktreeBlob()
  const expected = headBlob()
  let state = '其他本地修改'
  if (current === expected) {
    state = '仓库版本（干净）'
  } else if (exists) {
    state = gitProbe(['apply', '--reverse', '--check', patch]) ? '已应用本机签名' : '其他本地修改'
  }
  console.log(`patch      : ${patch}${exists ? '' : '（不存在）'}`)
  console.log(`状态       : ${state}`)
  console.log(`blob       : ${current}`)
  console.log(`HEAD blob  : ${expected}`)
  console.log(`暂存       : ${staged() === '' ? '无' : staged()}`)
  console.log(`其他改动   : ${git(['status', '--short']).split('\n').filter(Boolean).length} 项`)
}

function main() {
  const action = process.argv[2]
  const patch = patchPath()
  if (action !== 'apply' && action !== 'restore' && action !== 'status') {
    console.error(usage)
    process.exitCode = 1
    return
  }
  try {
    if (action === 'apply') {
      if (!fs.existsSync(patch)) {
        console.error(`仓库外签名 patch 不存在: ${patch}`)
        console.error('在本机签名配置可用的状态下生成一次，然后还原仓库文件:')
        console.error(`  git diff -- ${TARGET} > "${patch}"   # 生成时必须处于已配置签名的状态`)
        console.error(`  git checkout -- ${TARGET}            # 生成后立刻还原`)
        process.exitCode = 1
        return
      }
      if (gitProbe(['apply', '--reverse', '--check', patch])) {
        console.log(`${TARGET} 已处于本机签名状态，无需重复应用。`)
        return
      }
      applyPatch(patch)
      return
    }
    if (action === 'restore') {
      restoreTarget()
      return
    }
    printStatus(patch)
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error))
    console.error(usage)
    process.exitCode = 1
  }
}

main()