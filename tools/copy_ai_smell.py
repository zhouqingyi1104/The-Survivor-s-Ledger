# -*- coding: utf-8 -*-
"""AI 味诊断（一次性分析工具，不入库）

统计玩家可见文案的“机器感”特征：
  1. 句长方差（越均匀越像机器）
  2. 抽象套语密度（盘算/分寸/体面/道理…）
  3. 具体名词密度（器物、身体、天气、声音）
  4. 对偶/格言句式（一句里两个分句，前半条件后半结论）
  5. 四字套语
  6. 开头模板重复（前两字相同的句子扎堆）
"""
import io
import json
import os
import re
import sys
from collections import Counter

CJK = re.compile(r'[\u4e00-\u9fff]')

# 抽象套语：讲道理用的词，不带画面
ABSTRACT = [
    '盘算', '分寸', '体面', '道理', '打算', '主意', '掂量', '斟酌', '琢磨',
    '界限', '边界', '情面', '取舍', '利害', '斟酌', '思量', '拿捏', '进退',
    '安稳', '妥帖', '妥帖', '踏实', '从容', '周全', '妥', '适宜', '分寸感',
    '心气', '心绪', '念想', '思虑', '计较', '周旋', '应承', '允诺', '商量',
    '彼此', '各自', '互相', '大家', '咱们', '自身', '本身', '关系', '处境',
    '选择', '决定', '判断', '考虑', '明白', '清楚', '理解', '清楚',
]
# 具体物：能看见、能摸到、能听见
CONCRETE = [
    '柴', '炭', '米', '水', '井', '缸', '锅', '碗', '刀', '斧', '锯', '锤',
    '门', '窗', '墙', '瓦', '梁', '炕', '灶', '灯', '油', '布', '绳', '钉',
    '药', '盐', '肉', '饼', '粥', '汤', '雪', '风', '雨', '雾', '霜', '日头',
    '月亮', '鸡', '狗', '鼠', '虫', '血', '伤', '咳', '喘', '汗', '手', '脚',
    '肩', '腰', '眼', '喉', '牙', '骨', '皮', '头', '背', '膝', '指',
    '竹篮', '纸条', '锁', '柜', '篮', '筐', '袋', '桶', '盆', '勺', '筷',
    '脚 step', '脚印', '影', '声', '响', '味', '烟', '灰', '土', '泥',
]
# 四字套语（典型 AI 腔）
FOUR = re.compile(
    r'(?:安安稳稳|稳稳当当|踏踏实实|清清楚楚|明明白白|妥妥帖帖|从容不迫|'
    r'各有各的|彼此彼此|相互|彼此之间|不失分寸|拿捏分寸|恰到好处|'
    r'不多不少|不急不缓|不卑不亢|有商有量|有来有往|心照不宣)'
)


def load_strings():
    """复刻 copy_lint 的收集口径"""
    out = []
    skip_files = {
        'scripts/core/life_memory_file.gd',
        'scripts/core/playtest_report.gd',
        'scripts/core/migrate.gd',
    }
    skip_calls = ('Director.note_choice(', 'push_error(', 'push_warning(',
                  'print(', 'printerr(')
    lit = re.compile(r'"((?:[^"\\\n]|\\.)*)"')

    for root, dirs, files in os.walk('scripts'):
        if 'dev' in root.split(os.sep):
            continue
        for f in files:
            if not f.endswith('.gd'):
                continue
            p = os.path.join(root, f).replace('\\', '/')
            if p in skip_files:
                continue
            lines = io.open(p, encoding='utf-8').read().split('\n')
            for i, line in enumerate(lines, 1):
                code = strip_comment(line)
                if any(c in code for c in skip_calls):
                    continue
                for m in lit.finditer(code):
                    t = m.group(1)
                    if CJK.search(t):
                        out.append((f'{p}:{i}', t))

    for f in sorted(os.listdir('data')):
        if not f.endswith('.json'):
            continue
        try:
            parsed = json.load(io.open(os.path.join('data', f), encoding='utf-8'))
        except Exception:
            continue
        walk(parsed, 'data/' + f, out)
    return out


def walk(v, where, out):
    if isinstance(v, dict):
        for k in v:
            if not str(k).startswith('_'):
                walk(v[k], where + '.' + str(k), out)
    elif isinstance(v, list):
        for i, x in enumerate(v):
            walk(x, f'{where}[{i}]', out)
    elif isinstance(v, str) and CJK.search(v):
        out.append((where, v))


def strip_comment(line):
    inside = escaped = False
    for i, ch in enumerate(line):
        if escaped:
            escaped = False
        elif ch == '\\':
            escaped = True
        elif ch == '"':
            inside = not inside
        elif ch == '#' and not inside:
            return line[:i]
    return line


def sentences(text):
    parts = re.split(r'[。！？；\n]', text)
    return [p for p in (s.strip() for s in parts) if len(CJK.findall(p)) >= 2]


def main():
    items = load_strings()
    print(f'玩家可见字符串：{len(items)} 条')
    total_cn = sum(len(CJK.findall(t)) for _, t in items)
    print(f'中文字数：{total_cn}')

    # 句长分布
    lens = []
    for _, t in items:
        for s in sentences(t):
            lens.append(len(CJK.findall(s)))
    lens.sort()
    if lens:
        n = len(lens)
        mean = sum(lens) / n
        var = sum((x - mean) ** 2 for x in lens) / n
        print(f'\n句子数 {n}，平均 {mean:.1f} 字，标准差 {var ** 0.5:.1f}')
        print(f'  最短 {lens[0]}，P10 {lens[n // 10]}，中位 {lens[n // 2]}，'
              f'P90 {lens[n * 9 // 10]}，最长 {lens[-1]}')

    # 套语 / 具体物
    joined = '\n'.join(t for _, t in items)
    print('\n抽象套语出现次数（前 20）：')
    ac = Counter()
    for w in ABSTRACT:
        c = joined.count(w)
        if c:
            ac[w] = c
    for w, c in ac.most_common(20):
        print(f'  {w}: {c}')
    abstract_total = sum(ac.values())
    print(f'  合计 {abstract_total} 次')

    cc = Counter()
    for w in CONCRETE:
        c = joined.count(w)
        if c:
            cc[w] = c
    concrete_total = sum(cc.values())
    print(f'\n具体物词合计 {concrete_total} 次（前 20）：')
    for w, c in cc.most_common(20):
        print(f'  {w}: {c}')
    if abstract_total:
        print(f'\n抽象/具体 比 = {abstract_total / concrete_total:.2f}' if concrete_total else '')

    # 四字套语
    four = FOUR.findall(joined)
    print(f'\n四字套语：{len(four)} 处 {Counter(four).most_common(8)}')

    # 对偶句：一句里恰好一个逗号/顿号分两半，两半长度接近
    pair = 0
    for _, t in items:
        for s in sentences(t):
            if s.count('，') == 1:
                a, b = s.split('，')
                la, lb = len(CJK.findall(a)), len(CJK.findall(b))
                if la >= 3 and lb >= 3 and abs(la - lb) <= 2:
                    pair += 1
    print(f'匀称对偶句（两半字数差 ≤2）：{pair} 处')

    # 开头模板
    starts = Counter()
    for _, t in items:
        for s in sentences(t):
            if len(s) >= 2:
                starts[s[:2]] += 1
    print('\n句首两字重复最多（前 15）：')
    for w, c in starts.most_common(15):
        print(f'  「{w}…」× {c}')

    # 最长的若干条（信息过载候选）
    longs = sorted(((len(CJK.findall(t)), w, t) for w, t in items), reverse=True)
    print('\n最长的 8 条：')
    for n, w, t in longs[:8]:
        print(f'  [{n} 字] {w}  {t[:70]}…')

    # 输出全量到临时文件供人工通读
    dst = 'build/copy_dump.txt'
    os.makedirs('build', exist_ok=True)
    with io.open(dst, 'w', encoding='utf-8') as f:
        for w, t in items:
            f.write(f'{w}\t{t}\n')
    print(f'\n全量已写到 {dst}')


if __name__ == '__main__':
    main()
