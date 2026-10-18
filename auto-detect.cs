using System;
using System.Collections.Generic;
using System.Text;

// Conservative recognition of the V6.38 / enhanced R7 code family. No fixed RVAs.
// Relative operands are resolved against PE sections, never treated as file offsets.
public sealed class EngineDetection
{
    public int PinOffset, ExeOffset, IntlOffset;
    public byte[] IntlOld, IntlNew;
    public int[] RelaxOffsets;
    public byte[] RelaxOld;
}

public sealed class EngineDetector
{
    sealed class Section { public int Raw, Size; public uint Rva, Flags, VirtualSize; }
    sealed class Function { public int Start, End; }
    readonly byte[] b;
    readonly List<Section> sections = new List<Section>();
    readonly List<Function> functions = new List<Function>();
    static Exception Bad(string detail) { return new InvalidOperationException("自动定位失败：" + detail + "。没有改动引擎。"); }
    void Range(int p, int n) { if (p < 0 || n < 0 || (long)p + n > b.Length) throw Bad("PE 数据越界"); }
    ushort U16(int p) { Range(p, 2); return BitConverter.ToUInt16(b, p); }
    uint U32(int p) { Range(p, 4); return BitConverter.ToUInt32(b, p); }
    int I32(int p) { Range(p, 4); return BitConverter.ToInt32(b, p); }
    int Off(long rva)
    {
        foreach (Section s in sections)
            if (rva >= s.Rva && rva < (long)s.Rva + s.Size) return checked(s.Raw + (int)(rva - s.Rva));
        throw Bad("引用不在文件映射区内");
    }
    long Rva(int off)
    {
        foreach (Section s in sections)
            if (off >= s.Raw && (long)off < (long)s.Raw + s.Size) return (long)s.Rva + off - s.Raw;
        throw Bad("位置不在 PE 节内");
    }
    long RelativeRva(int operand) { return Rva(operand) + 4 + I32(operand); }
    int Relative(int operand) { return Off(RelativeRva(operand)); }
    bool WritableData(long rva) { foreach (Section s in sections) if (rva >= s.Rva && rva < (long)s.Rva + Math.Max(s.VirtualSize, (uint)s.Size)) return (s.Flags & 0xa0000000) == 0x80000000; return false; }
    bool Code(int p) { foreach (Section s in sections) if (p >= s.Raw && (long)p < (long)s.Raw + s.Size) return (s.Flags & 0x20000000) != 0; return false; }
    Function Owner(int p)
    {
        Function result = null;
        foreach (Function f in functions) if (p >= f.Start && p < f.End) { if (result != null) throw Bad("函数范围重叠"); result = f; }
        if (result == null) throw Bad("缺少函数边界");
        return result;
    }
    EngineDetector(byte[] bytes)
    {
        b = bytes;
        if (U16(0) != 0x5a4d) throw Bad("不是 PE 文件");
        int pe = checked((int)U32(60));
        if (U32(pe) != 0x4550 || U16(pe + 4) != 0x8664 || (U16(pe + 22) & 0x2000) == 0) throw Bad("不是 x64 DLL");
        int count = U16(pe + 6), optionalSize = U16(pe + 20), opt = pe + 24;
        if (count < 1 || count > 96 || optionalSize < 144 || U16(opt) != 0x20b || U32(opt + 108) < 4) throw Bad("不支持的 PE 结构");
        Range(opt, optionalSize + count * 40);
        for (int i = 0; i < count; i++)
        {
            int p = opt + optionalSize + i * 40;
            Section s = new Section { VirtualSize = U32(p + 8), Rva = U32(p + 12), Size = checked((int)U32(p + 16)), Raw = checked((int)U32(p + 20)), Flags = U32(p + 36) };
            Range(s.Raw, s.Size);
            if (s.Size == 0) continue;
            foreach (Section other in sections)
                if ((s.Raw < (long)other.Raw + other.Size && other.Raw < (long)s.Raw + s.Size) ||
                    (s.Rva < (long)other.Rva + other.Size && other.Rva < (long)s.Rva + s.Size)) throw Bad("PE 节重叠");
            sections.Add(s);
        }
        int pdata = Off(U32(opt + 136)), size = checked((int)U32(opt + 140));
        Range(pdata, size);
        if (size == 0 || size % 12 != 0 || Off((long)U32(opt + 136) + size - 1) != pdata + size - 1) throw Bad("异常表无效");
        for (int p = pdata; p < pdata + size; p += 12)
        {
            uint start = U32(p), end = U32(p + 4);
            if (start >= end) throw Bad("函数范围无效");
            int a = Off(start), z = Off((long)end - 1) + 1;
            if (z <= a || !Code(a) || !Code(z - 1)) throw Bad("函数不在代码节");
            functions.Add(new Function { Start = a, End = z });
        }
    }
    static int[] Pattern(string text)
    {
        string[] parts = text.Split(new char[] { ' ' }, StringSplitOptions.RemoveEmptyEntries);
        int[] result = new int[parts.Length];
        for (int i = 0; i < parts.Length; i++) result[i] = parts[i] == "??" ? -1 : Convert.ToInt32(parts[i], 16);
        return result;
    }
    bool Match(int p, int[] pattern)
    {
        if (p < 0 || (long)p + pattern.Length > b.Length) return false;
        for (int i = 0; i < pattern.Length; i++) if (pattern[i] >= 0 && b[p + i] != pattern[i]) return false;
        return true;
    }
    List<int> Find(string text)
    {
        int[] pattern = Pattern(text);
        List<int> hits = new List<int>();
        foreach (Section s in sections)
        {
            if ((s.Flags & 0x20000000) == 0) continue;
            for (int p = s.Raw; p <= s.Raw + s.Size - pattern.Length; p++) if (Match(p, pattern)) hits.Add(p);
        }
        return hits;
    }
    bool HashString(int p)
    {
        if (p < 0 || (long)p + 65 > b.Length || Code(p) || b[p + 64] != 0) return false;
        for (int i = 0; i < 64; i++) if (!((b[p+i] >= '0' && b[p+i] <= '9') || (b[p+i] >= 'a' && b[p+i] <= 'f'))) return false;
        return true;
    }
    bool Wide(int p, string text)
    {
        byte[] value = Encoding.Unicode.GetBytes(text + "\0");
        if (p < 0 || (long)p + value.Length > b.Length || Code(p)) return false;
        for (int i = 0; i < value.Length; i++) if (b[p+i] != value[i]) return false;
        return true;
    }
    EngineDetection Detect()
    {
        List<int> exe = Find("48 89 5C 24 08 48 89 7C 24 10 4C 89 74 24 18 55 48 8D AC 24 70 00 FF FF B8 90 00 01 00 E8 ?? ?? ?? ?? 48 2B E0 48 8B 05 ?? ?? ?? ?? 48 33 C4 48 89 85 80 FF 00 00 33 D2 41 B8 00 00 01 00 48 8D 4D 80 E8 ?? ?? ?? ?? 41 B8 00 80 00 00 48 8D 55 80 33 C9 FF 15");
        List<int> comparisons = Find("41 B8 40 00 00 00 48 8D 15 ?? ?? ?? ?? E8 ?? ?? ?? ?? 85 C0");
        List<int> validExe = new List<int>(), pins = new List<int>();
        foreach (int p in exe)
        {
            Function f = Owner(p);
            if (f.Start != p || f.End - p > 4096) continue;
            List<int> localPins = new List<int>();
            foreach (int c in comparisons)
                if (c >= p && c + 20 <= f.End) { int target = Relative(c + 9); if (HashString(target)) localPins.Add(target); }
            if (localPins.Count == 2 && localPins[0] != localPins[1]) { validExe.Add(p); pins.Add(localPins[0]); }
        }
        if (validExe.Count != 1) throw Bad("主程序哈希检查函数不是唯一匹配（可能已打补丁或代码已变化）");

        List<int> intl = Find("41 83 CF 04 44 89 7C 24 30 48 8D 15 ?? ?? ?? ?? 48 8D 4C 24 40 E8 ?? ?? ?? ?? 0F B6 D8 41 83 E7 FB 44 89 7C 24 30 48 8B 54 24 58 48 83 FA 07");
        List<int> intlOperands = new List<int>(), intlTargets = new List<int>();
        foreach (int p in intl)
        {
            int operand = p + 12, target = Relative(operand);
            if (!Wide(target, "yysls.exe")) continue;
            if (Owner(p).End < p + 47 || !Code(Relative(p + 22))) throw Bad("游戏名检查调用无效");
            // This family stores both client names next to each other. Do not choose
            // an unrelated occurrence of wwm.exe elsewhere in the DLL.
            List<int> names = new List<int>();
            for (int q = Math.Max(0, target - 64); q <= target + 64; q += 2) if (Wide(q, "wwm.exe")) names.Add(q);
            if (names.Count != 1) throw Bad("国际服游戏名字符串不是唯一匹配");
            intlOperands.Add(operand); intlTargets.Add(names[0]);
        }
        if (intlOperands.Count != 1) throw Bad("游戏名检查不是唯一匹配");

        string counter = "E8 ?? ?? ?? ?? 8B C0 48 C1 E0 06 48 8D 0D ?? ?? ?? ?? F0 48 FF 04 08 E9 ?? ?? ?? ?? 45 84 ";
        List<int> relaxA = Find(counter + "E4 74 39 48 8B 02 8B 48 10 89 4D 90 45 84 F6 75 ?? 44 38 B2 84 00 00 00 75 ?? 8B 40 14 39 82 80 00 00 00 72 ?? 44 38 B2 85 00 00 00 74 ?? 44 38 B2 86 00 00 00 74");
        List<int> relaxB = Find(counter + "ED 74 3A 48 8B 02 44 8B 40 10 44 89 45 90 45 84 F6 75 31 44 38 B2 84 00 00 00 75 28 8B 40 14 39 82 80 00 00 00 72 1D 44 38 B2 85 00 00 00 74 14 44 38 B2 86 00 00 00 74");
        if (relaxA.Count != 3 || relaxB.Count != 1) throw Bad("材质检查没有完整匹配到 3 + 1 处");
        List<int> relax = new List<int>(relaxA); relax.AddRange(relaxB); relax.Sort();
        int callTarget = -1;
        long counterTarget = -1;
        HashSet<int> owners = new HashSet<int>();
        foreach (int p in relax)
        {
            Function f = Owner(p);
            if (!owners.Add(f.Start) || f.End <= p + 96 || Owner(p + 33).Start != f.Start) throw Bad("材质检查函数边界不符");
            int call = Relative(p + 1), exit = Relative(p + 24);
            long data = RelativeRva(p + 14);
            if (!Code(call) || !WritableData(data) || exit < p + 33 || exit >= f.End) throw Bad("材质检查引用无效");
            if (callTarget >= 0 && (callTarget != call || counterTarget != data)) throw Bad("材质检查没有共用计数逻辑");
            callTarget = call; counterTarget = data;
        }
        int disp = checked((int)(Rva(intlTargets[0]) - Rva(intlOperands[0]) - 4));
        EngineDetection result = new EngineDetection { ExeOffset = validExe[0], PinOffset = pins[0], IntlOffset = intlOperands[0], IntlOld = new byte[4], IntlNew = BitConverter.GetBytes(disp), RelaxOffsets = new int[4], RelaxOld = new byte[4] };
        Array.Copy(b, result.IntlOffset, result.IntlOld, 0, 4);
        for (int i = 0; i < 4; i++) { result.RelaxOffsets[i] = relax[i] + 32; result.RelaxOld[i] = b[relax[i] + 32]; }
        return result;
    }
    public static EngineDetection Locate(byte[] bytes) { return new EngineDetector(bytes).Detect(); }
}
