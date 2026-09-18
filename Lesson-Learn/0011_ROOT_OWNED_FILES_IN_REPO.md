# 仓库里混进 root 拥有的文件：git 只对**某些**文件报权限错

> 日期：2026-09-18　|　相关配置：无（这是仓库状态问题，不是配置问题）
>
> 触发场景：`git add -A && git commit` 提交一批改动时突然失败，
> 而前一天同样的命令是好的。

## 问题症状

```
❯ git add -A && git commit -F GIT_COMMIT_MESSAGE.txt
error: insufficient permission for adding an object to repository database .git/objects
error: modules/common.nix: failed to insert into database
error: unable to index file 'modules/common.nix'
fatal: updating files failed
```

三个迷惑人的地方：

1. **只有 `modules/common.nix` 失败。** 同一批里别的文件
   （`modules/claude-code-manifest.json` 等）`git add` 得好好的，
   已经成功进了 index。
2. **文件本身权限正常。** `ls -l modules/common.nix` 是 `toru:users`，可读可写。
   报错说的是 `.git/objects`，不是这个文件。
3. **前一天是好的。** 同样的仓库、同样的命令、同样的用户。

## 根本原因分析

### 一、全仓库只有三个条目属于 root

```bash
find . ! -user toru -printf '%u:%g  %p\n'
```

```
root:root  ./flake.lock
root:root  ./.git/objects/e6
root:root  ./.git/objects/e6/9de29bb2d1d6434b8b29ae775ad8c2e48c5391
```

`.git/objects/e6` 的权限是 `drwxr-xr-x` —— 属主 root，其他人只能读不能写。
`toru` 往里面写任何东西都会被拒绝。

（那个对象 `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` 是 git 里著名的
**空 blob**，即空文件的 SHA-1。它本身是个完全正常的对象，问题只在属主。）

### 二、为什么偏偏是 `modules/common.nix`

git 的松散对象按 **SHA-1 的前两位**分目录存放：
哈希 `abcdef...` 的对象存到 `.git/objects/ab/cdef...`。

```bash
❯ git hash-object modules/common.nix
e69f383569edfcaa61117e40bfd4e8d5f46807cf
```

前两位是 **`e6`** —— 它必须写进 `.git/objects/e6/`，而那个目录恰好是 root 的。

其它文件的哈希前两位落在别的目录（那些目录都是 `toru` 的），所以一路顺利。

**这就是「只对某些文件失败」的全部原因：纯粹看哈希前缀的运气。**
换一批文件、或者把 `common.nix` 改一个字符让哈希变了，报错的文件就会换一个 ——
这种随机性很容易把人引向错误的方向，比如去怀疑那个文件本身有什么问题。

### 三、root 的东西是怎么进来的

看时间戳，这是**老账**，不是当天那次操作造成的：

| 条目 | 创建/修改时间 |
|------|---------------|
| `.git/objects/e6`（目录） | 2026-09-06 |
| 空 blob 对象 | 2026-09-12 |
| `flake.lock` | 2026-09-16 09:40 |

根因是 **`sudo nixos-rebuild switch --flake .`**：

- 当 `flake.lock` 需要更新时，nix 以 **root** 身份重写它 ——
  于是 `flake.lock` 变成 `root:root`。
- 读取 **dirty** 的 git 工作树时，nix 会调用 git，
  可能往 `.git/objects` 里写入对象 —— 于是那些对象和它们的分目录变成 root 的。

一旦写过，属主就永久留在那里了，之后的普通用户操作全部撞墙。

### 四、更隐蔽的那条线索：`flake.lock`

`flake.lock` 是 `root:root` 且 `644`，意味着 **toru 不可写**。

git 那个报错至少还吵得很大声；`flake.lock` 这条会安静地潜伏到你下次
`nix flake update` 才爆，而那时你多半已经忘了这件事。

**排查权限问题时不要只看 `.git/`，要扫整个仓库。**

## 已实施的修复

```bash
sudo chown -R toru:users /home/toru/nixos-config
```

改完 `git add -A && git commit` 立刻恢复正常。

> 注意 `toru` 的主组是 `users`（gid 100），不是 `toru`。
> `id` 一下再写，别想当然写成 `toru:toru`。

## 为什么这样解决

`chown -R` 是对症的：这些文件的**内容完全没问题**，
空 blob 是合法的 git 对象，`flake.lock` 也是正确的锁文件，
坏掉的只有属主。删掉重建反而会丢东西（`flake.lock` 删了得重新解析）。

范围上选了整个仓库而不是只 `chown` 那三个条目 —— 因为已经用
`find . ! -user toru` 扫过全仓库，确认只有那三个；整目录 `chown`
更简单，也顺带兜住任何漏网的。

## 后续注意事项

### 预防（按有效程度排序）

1. **`nix flake update` 永远以 toru 跑，绝不加 sudo。**
   这是 `flake.lock` 变成 root 的直接原因。

2. **rebuild 之前先以普通用户跑一次 `nix build`。**
   这已经写进 [CLAUDE.md](../CLAUDE.md) 的重建顺序第 3 步。
   用户态构建时 `flake.lock` 已经以 toru 的身份写好了，
   轮到 root 阶段它没东西可写，也就没机会改属主。
   **这一步不只是「提前发现错误」，它同时是这个权限问题的根本预防。**

3. 更硬的办法（**尚未采用**）：给 `nrb` 别名加 `--no-write-lock-file`。
   这样 lock 过期时 rebuild 会**显式报错**，而不是偷偷以 root 改写。
   代价是 lock 一过期就得先手动 `nix flake update`。
   要用的话改 `home/toru.nix` 的 `commonAliases`。

### 自查

跑过任何 `sudo` 之后，偶尔查一下：

```bash
find . ! -user toru -printf '%u  %p\n'
```

**应该没有任何输出。** 有输出就 `sudo chown -R toru:users .`。

### 认知要点

- **`insufficient permission for adding an object to repository database`
  不是说你对那个源文件没权限**，而是说你对 `.git/objects/<哈希前两位>/`
  这个目录没写权限。看到这个报错先扫属主，别去研究那个被点名的文件。
- 报错点名哪个文件是**随机的**，取决于哈希前缀。不要根据它去推断问题范围。

## 相关文档

- [CLAUDE.md](../CLAUDE.md) —— 「改完 nix 文件后的重建顺序」第 3 步与「反复出现的坑」第 5 条
- [000B_HOME_MANAGER_ACTIVATION_CONFLICT.md](000B_HOME_MANAGER_ACTIVATION_CONFLICT.md) —— 另一个「报错信息指向的地方不是真正病灶」的例子
- [0010_CLAUDE_CODE_VERSION_PINNING.md](0010_CLAUDE_CODE_VERSION_PINNING.md) —— 同一批操作里的另一条 flake 相关结论
