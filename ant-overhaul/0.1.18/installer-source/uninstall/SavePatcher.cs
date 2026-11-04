using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace AntOverhaulUninstall
{
    public sealed class CreatureRecord
    {
        public int Index { get; internal set; }
        public int HealthOffset { get; internal set; }
        public float Health { get; internal set; }
        public string ClassPath { get; internal set; }
        public int Level { get; internal set; }
        public int Owner { get; internal set; }
        public int AssignedTile { get; internal set; }
        public int TennancyArrayNo { get; internal set; }
        public float SpawnStatScailing { get; internal set; }
        public bool IsSubTenant { get; internal set; }
        // Older saves omit this property. Absence is not silently treated as false.
        public bool? IsForeignSubTenant { get; internal set; }
        public int? CreatureScaleLevel { get; internal set; }
        public ReadOnlyCollection<string> ActorTags { get; internal set; }
        public bool HasCapturedSnapshot { get; internal set; }
    }

    public sealed class SaveDocument
    {
        internal byte[] Original, Gvas;
        internal List<CompressedBlock> Blocks;
        public ReadOnlyCollection<CreatureRecord> Creatures { get; internal set; }
        public string CreatureArrayName { get; internal set; }
        public bool IsCompressed { get { return Blocks != null; } }
        public int GvasLength { get { return Gvas.Length; } }
        public string LevelName { get; internal set; }
        public string LinkedFormicariumSave { get; internal set; }
        public bool HasOwnedColonyIds { get; internal set; }
        public ReadOnlyCollection<int> OwnedColonyIds { get; internal set; }
        public int? StartingColonyId { get; internal set; }
        public byte[] GetGvasBytes() { return (byte[])Gvas.Clone(); }

        public byte[] Patch(IDictionary<int, float> capByRecordIndex)
        {
            if (capByRecordIndex == null) throw new ArgumentNullException("capByRecordIndex");
            byte[] changed = (byte[])Gvas.Clone();
            HashSet<int> allowed = new HashSet<int>();
            foreach (KeyValuePair<int, float> pair in capByRecordIndex)
            {
                if (pair.Key < 0 || pair.Key >= Creatures.Count || !SavePatcher.Finite(pair.Value) || pair.Value <= 0)
                    throw new ArgumentException("Invalid creature index or native health cap.");
                CreatureRecord record = Creatures[pair.Key];
                if (record.Health <= pair.Value) continue;
                byte[] replacement = BitConverter.GetBytes(pair.Value);
                Buffer.BlockCopy(replacement, 0, changed, record.HealthOffset, 4);
                for (int n = 0; n < 4; n++) allowed.Add(record.HealthOffset + n);
            }
            if (allowed.Count == 0) return (byte[])Original.Clone();
            HashSet<int> actualChanges = new HashSet<int>();
            for (int i = 0; i < Gvas.Length; i++)
            {
                if (Gvas[i] == changed[i]) continue;
                if (!allowed.Contains(i)) throw new InvalidDataException("A non-health byte changed.");
                actualChanges.Add(i);
            }
            byte[] output = Blocks == null ? changed : SavePatcher.Repack(this, changed, actualChanges);
            SaveDocument verify = SavePatcher.Read(output);
            if (!SavePatcher.Equal(changed, verify.Gvas)) throw new InvalidDataException("Repacked GVAS differs from exact health patch.");
            if (verify.Creatures.Count != Creatures.Count) throw new InvalidDataException("Creature count changed during patch.");
            for (int i = 0; i < Creatures.Count; i++)
            {
                float cap;
                float expected = capByRecordIndex.TryGetValue(i, out cap) ? Math.Min(Creatures[i].Health, cap) : Creatures[i].Health;
                if (verify.Creatures[i].Health != expected || verify.Creatures[i].HealthOffset != Creatures[i].HealthOffset)
                    throw new InvalidDataException("Health patch read-back mismatch.");
            }
            return output;
        }
    }

    internal sealed class CompressedBlock
    {
        internal int FileOffset, CompressedLength, RawOffset, RawLength;
    }

    internal sealed class PropertyTag
    {
        internal string Name, Kind, Inner, StructName;
        internal int Start, Payload, End, Size, ArrayIndex;
        internal bool? Bool;
    }

    internal sealed class GvasReader
    {
        internal readonly byte[] Data;
        private static readonly Encoding Utf8 = new UTF8Encoding(false, true);
        private static readonly Encoding Utf16 = new UnicodeEncoding(false, false, true);
        private static readonly HashSet<string> Kinds = new HashSet<string>(StringComparer.Ordinal)
        {
            "IntProperty", "Int8Property", "Int16Property", "Int64Property", "UInt16Property", "UInt32Property", "UInt64Property",
            "FloatProperty", "DoubleProperty", "BoolProperty", "ByteProperty", "EnumProperty", "NameProperty", "StrProperty",
            "TextProperty", "ObjectProperty", "SoftObjectProperty", "WeakObjectProperty", "LazyObjectProperty", "ClassProperty",
            "SoftClassProperty", "InterfaceProperty", "StructProperty", "ArrayProperty", "MapProperty", "SetProperty",
            "DelegateProperty", "MulticastDelegateProperty"
        };
        internal GvasReader(byte[] data) { Data = data; }
        internal void Bounds(int offset, long length, int limit)
        {
            if (offset < 0 || length < 0 || limit < 0 || limit > Data.Length || (long)offset + length > limit)
                throw new InvalidDataException("Serialized field exceeds its declared boundary.");
        }
        internal int I32(ref int p, int limit) { Bounds(p, 4, limit); int v = BitConverter.ToInt32(Data, p); p += 4; return v; }
        internal byte U8(ref int p, int limit) { Bounds(p, 1, limit); return Data[p++]; }
        internal string String(ref int p, int limit)
        {
            int count = I32(ref p, limit);
            if (count == 0) return "";
            if (count == Int32.MinValue) throw new InvalidDataException("Invalid FString length.");
            long length = Math.Abs((long)count) * (count < 0 ? 2 : 1);
            Bounds(p, length, limit);
            int tail = count < 0 ? 2 : 1;
            if (Data[p + (int)length - 1] != 0 || (tail == 2 && Data[p + (int)length - 2] != 0))
                throw new InvalidDataException("Unterminated FString.");
            string result;
            try { result = (count < 0 ? Utf16 : Utf8).GetString(Data, p, (int)length - tail); }
            catch (DecoderFallbackException e) { throw new InvalidDataException("Invalid FString encoding.", e); }
            p += (int)length;
            return result;
        }
        internal PropertyTag Tag(int start, int limit)
        {
            int p = start;
            PropertyTag tag = new PropertyTag { Start = start, Name = String(ref p, limit) };
            if (tag.Name == "None") { tag.End = p; return tag; }
            if (System.String.IsNullOrEmpty(tag.Name)) throw new InvalidDataException("Empty property name.");
            tag.Kind = String(ref p, limit);
            if (!Kinds.Contains(tag.Kind)) throw new InvalidDataException("Unsupported property type: " + tag.Kind);
            tag.Size = I32(ref p, limit); tag.ArrayIndex = I32(ref p, limit);
            if (tag.Size < 0 || tag.ArrayIndex < 0) throw new InvalidDataException("Invalid property size/index.");
            if (tag.Kind == "StructProperty")
            {
                tag.StructName = String(ref p, limit); Bounds(p, 16, limit); p += 16;
            }
            else if (tag.Kind == "ArrayProperty" || tag.Kind == "SetProperty") tag.Inner = String(ref p, limit);
            else if (tag.Kind == "MapProperty") { String(ref p, limit); String(ref p, limit); }
            else if (tag.Kind == "ByteProperty" || tag.Kind == "EnumProperty") String(ref p, limit);
            else if (tag.Kind == "BoolProperty")
            {
                byte value = U8(ref p, limit);
                if (value > 1 || tag.Size != 0) throw new InvalidDataException("Invalid boolean property.");
                tag.Bool = value == 1;
            }
            byte guid = U8(ref p, limit);
            if (guid > 1) throw new InvalidDataException("Invalid property GUID flag.");
            if (guid != 0) { Bounds(p, 16, limit); p += 16; }
            Bounds(p, tag.Size, limit); tag.Payload = p; tag.End = p + tag.Size;
            return tag;
        }
        internal Dictionary<string, PropertyTag> Properties(ref int p, int limit)
        {
            Dictionary<string, PropertyTag> fields = new Dictionary<string, PropertyTag>(StringComparer.Ordinal);
            while (p < limit)
            {
                PropertyTag t = Tag(p, limit); p = t.End;
                if (t.Name == "None") return fields;
                if (fields.ContainsKey(t.Name) || t.ArrayIndex != 0) throw new InvalidDataException("Duplicate or indexed property.");
                fields.Add(t.Name, t);
            }
            throw new InvalidDataException("Missing property None terminator.");
        }
        internal Dictionary<string, PropertyTag> Root(string expectedClass)
        {
            if (Data.Length < 28 || !SavePatcher.Magic(Data, "GVAS")) throw new InvalidDataException("Missing GVAS header.");
            int p = 4;
            if (I32(ref p, Data.Length) != 2) throw new InvalidDataException("Unsupported GVAS version.");
            int packageVersion = I32(ref p, Data.Length);
            if (packageVersion != 518 && packageVersion != 522) throw new InvalidDataException("Unsupported UE4 save package version.");
            Bounds(p, 10, Data.Length);
            if (BitConverter.ToUInt16(Data, p) != 4) throw new InvalidDataException("Unsupported engine save header.");
            p += 10; String(ref p, Data.Length);
            if (I32(ref p, Data.Length) != 3) throw new InvalidDataException("Unsupported custom-version format.");
            int versions = I32(ref p, Data.Length);
            if (versions < 0) throw new InvalidDataException("Invalid custom-version count.");
            Bounds(p, (long)versions * 20, Data.Length); p += versions * 20;
            if (String(ref p, Data.Length) != expectedClass) throw new InvalidDataException("Unexpected save-game class.");
            Dictionary<string, PropertyTag> root = Properties(ref p, Data.Length);
            if (Data.Length - p != 4 || I32(ref p, Data.Length) != 0) throw new InvalidDataException("Unknown GVAS trailer.");
            return root;
        }
        internal PropertyTag Require(Dictionary<string, PropertyTag> fields, string name, string kind, int size)
        {
            PropertyTag t;
            if (!fields.TryGetValue(name, out t) || t.Kind != kind || (size >= 0 && t.Size != size))
                throw new InvalidDataException("Missing or invalid property: " + name);
            return t;
        }
        internal int Int(Dictionary<string, PropertyTag> fields, string name)
        { PropertyTag t = Require(fields, name, "IntProperty", 4); return BitConverter.ToInt32(Data, t.Payload); }
        internal float Float(Dictionary<string, PropertyTag> fields, string name)
        {
            PropertyTag t = Require(fields, name, "FloatProperty", 4);
            float value = BitConverter.ToSingle(Data, t.Payload);
            if (!SavePatcher.Finite(value)) throw new InvalidDataException("Non-finite saved scalar: " + name);
            return value;
        }
        internal List<string> NameArray(Dictionary<string, PropertyTag> fields, string name)
        {
            PropertyTag tag;
            List<string> result = new List<string>();
            if (!fields.TryGetValue(name, out tag)) return result;
            if (tag.Kind != "ArrayProperty" || tag.Inner != "NameProperty") throw new InvalidDataException("Invalid actor tag array.");
            int position = tag.Payload, count = I32(ref position, tag.End);
            if (count < 0 || count > 4096 || count > (tag.End - position) / 5) throw new InvalidDataException("Invalid actor tag count.");
            for (int i = 0; i < count; i++)
            {
                string value = String(ref position, tag.End);
                if (value.Length > 2048 || value.IndexOf('\0') >= 0) throw new InvalidDataException("Invalid actor tag.");
                result.Add(value);
            }
            if (position != tag.End) throw new InvalidDataException("Actor tags do not end at the declared boundary.");
            return result;
        }
        internal bool Boolean(Dictionary<string, PropertyTag> fields, string name)
        { return Require(fields, name, "BoolProperty", 0).Bool.Value; }
        internal string ValueString(PropertyTag t, string kind)
        {
            if (t.Kind != kind) throw new InvalidDataException("Unexpected string property type: " + t.Name);
            int p = t.Payload; string value = String(ref p, t.End);
            if (p != t.End) throw new InvalidDataException("String payload does not fill property.");
            return value;
        }
    }

    public static class SavePatcher
    {
        internal static bool Finite(float f) { return !Single.IsNaN(f) && !Single.IsInfinity(f); }
        internal static bool Magic(byte[] bytes, string value)
        {
            if (bytes.Length < value.Length) return false;
            for (int i = 0; i < value.Length; i++) if (bytes[i] != (byte)value[i]) return false;
            return true;
        }
        internal static bool Equal(byte[] a, byte[] b)
        {
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++) if (a[i] != b[i]) return false;
            return true;
        }
        private static ulong U64(byte[] data, int p)
        { if (p < 0 || (long)p + 8 > data.Length) throw new InvalidDataException("Truncated PMOC header."); return BitConverter.ToUInt64(data, p); }
        private static uint Adler(byte[] data)
        {
            uint a = 1, b = 0;
            for (int i = 0; i < data.Length; i++) { a = (a + data[i]) % 65521; b = (b + a) % 65521; }
            return (b << 16) | a;
        }
        private static byte[] Inflate(byte[] file, int start, int length, int expected)
        {
            if (length < 6 || (long)start + length > file.Length) throw new InvalidDataException("Truncated zlib block.");
            byte cmf = file[start], flg = file[start + 1];
            if ((cmf & 15) != 8 || (cmf >> 4) > 7 || ((cmf << 8) + flg) % 31 != 0 || (flg & 32) != 0)
                throw new InvalidDataException("Unsupported zlib header.");
            uint checksum = ((uint)file[start + length - 4] << 24) | ((uint)file[start + length - 3] << 16) | ((uint)file[start + length - 2] << 8) | file[start + length - 1];
            byte[] raw = new byte[expected];
            // Single-byte input avoids DeflateStream reading beyond the final deflate block,
            // allowing trailing compressed bytes to be rejected instead of ignored.
            using (ExactInput input = new ExactInput(file, start + 2, length - 6))
            using (DeflateStream deflate = new DeflateStream(input, CompressionMode.Decompress, true))
            {
                int offset = 0;
                while (offset < raw.Length)
                {
                    int n = deflate.Read(raw, offset, raw.Length - offset);
                    if (n == 0) throw new InvalidDataException("Truncated inflated block.");
                    offset += n;
                }
                if (deflate.ReadByte() != -1 || input.Position != input.Length) throw new InvalidDataException("Compressed block size does not match decoded data.");
            }
            if (Adler(raw) != checksum) throw new InvalidDataException("Zlib Adler32 mismatch.");
            return raw;
        }
        private static byte[] Deflate(byte[] raw)
        {
            using (MemoryStream result = new MemoryStream())
            {
                result.WriteByte(0x78); result.WriteByte(0x9c);
                using (DeflateStream stream = new DeflateStream(result, CompressionLevel.Optimal, true)) stream.Write(raw, 0, raw.Length);
                uint checksum = Adler(raw);
                result.WriteByte((byte)(checksum >> 24)); result.WriteByte((byte)(checksum >> 16)); result.WriteByte((byte)(checksum >> 8)); result.WriteByte((byte)checksum);
                return result.ToArray();
            }
        }
        private static SaveDocument Decode(byte[] bytes)
        {
            if (!BitConverter.IsLittleEndian) throw new PlatformNotSupportedException("Little-endian Windows is required.");
            if (bytes == null) throw new ArgumentNullException("bytes");
            SaveDocument document = new SaveDocument { Original = (byte[])bytes.Clone() };
            if (Magic(bytes, "GVAS")) { document.Gvas = (byte[])bytes.Clone(); return document; }
            if (!Magic(bytes, "PMOC")) throw new InvalidDataException("Unknown save wrapper.");
            List<CompressedBlock> blocks = new List<CompressedBlock>();
            int cursor = 4, totalRaw = 0;
            while (cursor < bytes.Length)
            {
                ulong magic = U64(bytes, cursor), chunkSize = U64(bytes, cursor + 8), totalCompressed = U64(bytes, cursor + 16), blockRaw = U64(bytes, cursor + 24), compressed = U64(bytes, cursor + 32), raw = U64(bytes, cursor + 40);
                if (magic != 0x9e2a83c1UL || chunkSize != 131072 || totalCompressed != compressed || blockRaw != raw || raw == 0 || raw > chunkSize || compressed < 6 || compressed > Int32.MaxValue)
                    throw new InvalidDataException("Unsupported PMOC chunk metadata.");
                if ((long)cursor + 48 + (long)compressed > bytes.Length || (long)totalRaw + (long)raw > Int32.MaxValue)
                    throw new InvalidDataException("PMOC block exceeds archive boundary.");
                blocks.Add(new CompressedBlock { FileOffset = cursor, CompressedLength = (int)compressed, RawOffset = totalRaw, RawLength = (int)raw });
                totalRaw += (int)raw; cursor += 48 + (int)compressed;
            }
            if (cursor != bytes.Length || totalRaw < 8 || blocks.Count == 0) throw new InvalidDataException("Invalid compressed archive extent.");
            byte[] decoded = new byte[totalRaw];
            foreach (CompressedBlock block in blocks)
            {
                byte[] raw = Inflate(bytes, block.FileOffset + 48, block.CompressedLength, block.RawLength);
                Buffer.BlockCopy(raw, 0, decoded, block.RawOffset, block.RawLength);
            }
            if (BitConverter.ToInt32(decoded, 0) != totalRaw - 4) throw new InvalidDataException("Decoded save size prefix mismatch.");
            document.Gvas = new byte[totalRaw - 4]; Buffer.BlockCopy(decoded, 4, document.Gvas, 0, document.Gvas.Length);
            if (!Magic(document.Gvas, "GVAS")) throw new InvalidDataException("Decoded save is not GVAS.");
            document.Blocks = blocks; return document;
        }
        public static void ValidateNativeMain(byte[] bytes)
        {
            SaveDocument document = Decode(bytes); GvasReader reader = new GvasReader(document.Gvas);
            Dictionary<string, PropertyTag> root = reader.Root("/Script/EotU.FormicSave");
            PropertyTag colony = reader.Require(root, "ColonySetup", "StructProperty", -1);
            if (colony.StructName != "ColonyData") throw new InvalidDataException("Unknown colony-setup struct.");
            int p = colony.Payload; reader.Properties(ref p, colony.End);
            if (p != colony.End) throw new InvalidDataException("Colony setup has trailing data.");
        }
        public static SaveDocument Read(byte[] bytes)
        {
            SaveDocument document = Decode(bytes); GvasReader reader = new GvasReader(document.Gvas);
            Dictionary<string, PropertyTag> root = reader.Root("/Script/EotU.EotUSaveGame");
            PropertyTag array, legacy;
            bool hasNew = root.TryGetValue("AllCreaturesSaveStates", out array), hasOld = root.TryGetValue("CreatureSaveStates", out legacy);
            if (hasNew == hasOld) throw new InvalidDataException("Expected one known creature-array layout.");
            if (!hasNew) array = legacy;
            if (array.Kind != "ArrayProperty" || array.Inner != "StructProperty") throw new InvalidDataException("Invalid creature-array tag.");
            document.CreatureArrayName = array.Name;
            int p = array.Payload, count = reader.I32(ref p, array.End);
            if (count < 0 || count > array.Size / 9) throw new InvalidDataException("Impossible creature count.");
            PropertyTag inner = reader.Tag(p, array.End);
            if (inner.Name != array.Name || inner.Kind != "StructProperty" || inner.StructName != "CreatureSaveState" || inner.ArrayIndex != 0 || inner.End != array.End)
                throw new InvalidDataException("Invalid creature-array struct metadata.");
            p = inner.Payload;
            List<CreatureRecord> records = new List<CreatureRecord>();
            for (int i = 0; i < count; i++)
            {
                Dictionary<string, PropertyTag> f = reader.Properties(ref p, inner.End);
                PropertyTag health = reader.Require(f, "Health", "FloatProperty", 4);
                string classPath = reader.ValueString(reader.Require(f, "CreatureType", "ObjectProperty", -1), "ObjectProperty");
                if (!classPath.StartsWith("/Game/", StringComparison.Ordinal) || classPath.IndexOf('\0') >= 0) throw new InvalidDataException("Invalid saved creature class path.");
                List<string> actorTags = reader.NameArray(f, "ActorTags");
                records.Add(new CreatureRecord {
                    Index = i, HealthOffset = health.Payload, Health = reader.Float(f, "Health"), ClassPath = classPath,
                    Owner = reader.Int(f, "OwningPlayer"), Level = reader.Int(f, "CreatureLevel"), AssignedTile = reader.Int(f, "AssignedTile"),
                    TennancyArrayNo = reader.Int(f, "TennancyArrayNo"), SpawnStatScailing = reader.Float(f, "SpawnStatScailing"),
                    IsSubTenant = reader.Boolean(f, "bIsSubTennent"),
                    IsForeignSubTenant = f.ContainsKey("bForeignSubTennent") ? (bool?)reader.Boolean(f, "bForeignSubTennent") : null,
                    CreatureScaleLevel = f.ContainsKey("CreatureScaleLevel") ? (int?)reader.Int(f, "CreatureScaleLevel") : null,
                    ActorTags = actorTags.AsReadOnly(), HasCapturedSnapshot = actorTags.Exists(t => t.StartsWith("EAA_SlaverCopy_v1:", StringComparison.Ordinal))
                });
            }
            if (p != inner.End) throw new InvalidDataException("Creature records do not end at declared array boundary.");
            document.Creatures = records.AsReadOnly();
            PropertyTag value;
            document.LevelName = root.TryGetValue("LevelToLoad", out value) ? reader.ValueString(value, "StrProperty") : null;
            document.LinkedFormicariumSave = root.TryGetValue("LinkedFormicariumSave", out value) ? reader.ValueString(value, "StrProperty") : null;
            document.StartingColonyId = root.ContainsKey("StartingColonyID") ? (int?)reader.Int(root, "StartingColonyID") : null;
            List<int> owned = new List<int>();
            if (root.TryGetValue("OwnedColonyIDs", out value))
            {
                if (value.Kind != "ArrayProperty" || value.Inner != "IntProperty") throw new InvalidDataException("Invalid owned-colony array.");
                p = value.Payload; int n = reader.I32(ref p, value.End);
                if (n < 0 || (long)n * 4 != value.End - p) throw new InvalidDataException("Owned-colony array size mismatch.");
                for (int i = 0; i < n; i++) owned.Add(reader.I32(ref p, value.End));
                document.HasOwnedColonyIds = true;
            }
            document.OwnedColonyIds = owned.AsReadOnly();
            return document;
        }
        internal static byte[] Repack(SaveDocument document, byte[] gvas, HashSet<int> changedHealthBytes)
        {
            using (MemoryStream output = new MemoryStream())
            {
                output.Write(document.Original, 0, 4);
                foreach (CompressedBlock block in document.Blocks)
                {
                    bool changed = false;
                    foreach (int offset in changedHealthBytes)
                        if (offset + 4 >= block.RawOffset && offset + 4 < block.RawOffset + block.RawLength) { changed = true; break; }
                    if (!changed)
                    {
                        output.Write(document.Original, block.FileOffset, 48 + block.CompressedLength); continue;
                    }
                    byte[] raw = new byte[block.RawLength];
                    int skip = 0;
                    if (block.RawOffset < 4)
                    {
                        byte[] prefix = BitConverter.GetBytes(gvas.Length); skip = Math.Min(4 - block.RawOffset, block.RawLength);
                        Buffer.BlockCopy(prefix, block.RawOffset, raw, 0, skip);
                    }
                    Buffer.BlockCopy(gvas, Math.Max(0, block.RawOffset - 4), raw, skip, block.RawLength - skip);
                    byte[] compressed = Deflate(raw), header = new byte[48];
                    Buffer.BlockCopy(document.Original, block.FileOffset, header, 0, 48);
                    Buffer.BlockCopy(BitConverter.GetBytes((ulong)compressed.Length), 0, header, 16, 8);
                    Buffer.BlockCopy(BitConverter.GetBytes((ulong)compressed.Length), 0, header, 32, 8);
                    output.Write(header, 0, header.Length); output.Write(compressed, 0, compressed.Length);
                }
                return output.ToArray();
            }
        }
        private sealed class ExactInput : Stream
        {
            private readonly byte[] _bytes; private readonly int _start, _length; private int _offset;
            internal ExactInput(byte[] bytes, int start, int length) { _bytes = bytes; _start = start; _length = length; }
            public override int Read(byte[] buffer, int offset, int count)
            {
                if (_offset == _length || count == 0) return 0;
                buffer[offset] = _bytes[_start + _offset++]; return 1;
            }
            public override bool CanRead { get { return true; } }
            public override bool CanSeek { get { return false; } }
            public override bool CanWrite { get { return false; } }
            public override long Length { get { return _length; } }
            public override long Position { get { return _offset; } set { throw new NotSupportedException(); } }
            public override void Flush() { }
            public override long Seek(long o, SeekOrigin s) { throw new NotSupportedException(); }
            public override void SetLength(long n) { throw new NotSupportedException(); }
            public override void Write(byte[] b, int o, int n) { throw new NotSupportedException(); }
        }
    }
}
