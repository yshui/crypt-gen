import std.stdio;
import sdlang;
import std.path;
import std.traits;
import std.ascii;
import std.exception : enforce;

///
string escape_char(Char)(Char c) if (isSomeChar!Char) {
    import std.format : format;
    import std.algorithm : canFind;
    if (c.isAlphaNum) {
        return c.format!"%c";
    }
    if (":_".canFind(c)) {
        return c.format!"%c";
    }
    return c.format!"\\x%2x";
}

///
string escape_string(string s) {
    import std.algorithm : map;
    import std.array : join;
    return s.map!escape_char.join("").idup;
}

///
string unit_name_from_path(P)(P p) if (is(typeof(asNormalizedPath(P.init)))) {
    import std.array : array, join;
    import std.algorithm : map;
    auto np = p.asAbsolutePath.asNormalizedPath.array.pathSplitter;
    assert(np.front == "/");
    np.popFront;
    if (np.empty) {
        return "-";
    }
    return np.map!((a) { return a.map!escape_char.join(""); }).join("-").idup;
}

unittest {
    assert("/dev/sdb".unit_name_from_path == "dev-sdb");
    assert("/dev sdb".unit_name_from_path == "dev\\x20sdb");
    assert("/dev-sdb".unit_name_from_path == "dev\\x2dsdb");
    assert("/dev\\sdb".unit_name_from_path == "dev\\x5csdb");
}

///
void check_keydev_dep(ref Tag config, in ref bool[string] all_devices) {
    foreach(k; config.maybe.tags["keyfile"]) {
        if ("dev" in k.attributes) {
            enforce(k.getAttribute!string("dev") in all_devices);
        }
    }
}

private void check_name(string name) {
    foreach(c; name) {
        enforce(c.isAlphaNum || c == '-');
    }
}

///
struct KeyFile {
private:
    string path_;
    string unit_;
    string name_;
public:
    ///
    this(ref Tag k) {
        if ("dev" in k.attributes) {
            path_ = "/dev/mapper/"~k.expectAttribute!string("dev");
            unit_ = path_.unit_name_from_path~".device";
        } else {
            path_ = k.expectAttribute!string("file");
            unit_ = null;
        }
        name_ = k.expectValue!string;
    }
    ///
    @property string path() {
        return path_;
    }
    ///
    @property string unit() {
        return unit_;
    }
    ///
    @property string name() {
        return name_;
    }
    ///
    void generate() {}
}

///
void generate_unit(ref Tag cfg, string out_dir, ref KeyFile[string] kfs) {
    import mustache : MustacheEngine;
    import std.algorithm : startsWith;
    import std.format : format;
    import std.file : exists;
    MustacheEngine!string mustache;
    immutable name = cfg.expectValue!string;
    immutable unit_name = name.escape_string.format!"systemd-cryptsetup@%s.service";
    auto out_unit = buildPath(out_dir, unit_name);
    if (out_unit.exists) {
        stderr.writefln("%s already exists.", out_unit);
        return;
    }
    auto ctx = new MustacheEngine!string.Context;
    ctx["name"] = name;
    if ("keyfile" in cfg.attributes) {
        auto kfname = cfg.expectAttribute!string("keyfile");
        immutable unit = kfs[kfname].unit;
        ctx["key"] = kfs[kfname].path;
        if (unit !is null) {
            auto sub = ctx.addSubContext("wants");
            sub["dep"] = unit;
        }
    } else {
        ctx["key"] = "-";
    }
    // Tear down before exiting initrd
    if (cfg.getAttribute("teardown", false)) {
        ctx.addSubContext("teardown?");
    }

    auto device_file = cfg.expectAttribute!string("dev");
    ctx["device_file"] = device_file;
    if (device_file.startsWith("/dev")) {
        auto sub = ctx.addSubContext("block?");
        sub["device"] = ctx["device_file"].unit_name_from_path~".device";
    }
    if ("options" in cfg.attributes) {
        ctx["options"] = cfg.expectAttribute!string("options");
    } else {
        ctx["options"] = "";
    }

    auto f = File(out_unit, "w");
    f.write(mustache.renderString(import("unit_template"), ctx));
    stderr.writefln("Units %s generated", out_unit);

    immutable req = buildPath(out_dir, "cryptsetup.target.requires");
    if (!req.exists) {
        import std.file : mkdir;
        req.mkdir;
    }

    import std.file : symlink;
    immutable link_path = buildPath(req, unit_name);
    out_unit.symlink(link_path);
    stderr.writefln("Units linked to %s", link_path);
}

void generate_udev_rules(ref Tag cfg) {
    auto f = File("/usr/lib/udev/rules.d/99-zz-systemd-ready.rules", "w");
    f.writeln("ACTION==\"remove\", GOTO=\"zz_override_end\"");
    foreach(k; cfg.maybe.tags["device"]) {
        if (k.getAttribute("blob", false)) {
            f.writefln("SUBSYSTEM==\"block\", ENV{DM_NAME}==\"%s\","~
                       " ENV{SYSTEMD_READY}=\"1\"", k.expectValue!string);
        }
    }
    f.writeln("LABEL=\"zz_override_end\"");
}

bool check_initrd() {
    auto f = File("/proc/mounts");
    foreach(l; f.byLine) {
        import std.array : split, array;
        auto p = l.split(' ').array;
        if (p[1] == "/" && p[2] == "rootfs") {
            return true;
        }
    }
    return false;
}

///
void main(string[] args)
{
    if (!check_initrd()) {
        stderr.writeln("Not in initrd, exiting");
        return;
    }
    // Try to write to dmesg
    try {
        auto f = File("/dev/kmsg", "w");
        stderr = f;
    } catch (Exception e) {
    }

    try {
        bool[string] all_devices;
        auto f = parseFile("/etc/crypttab.sdl");
        foreach(k; f.maybe.tags["device"]) {
            immutable name = k.expectValue!string;
            name.check_name;
            all_devices[name] = true;
        }
        check_keydev_dep(f, all_devices);

        KeyFile[string] kfs;
        foreach(k; f.maybe.tags["keyfile"]) {
            auto kf = KeyFile(k);
            kfs[kf.name] = kf;
        }
        foreach(k; f.maybe.tags["device"]) {
            k.generate_unit(args[1], kfs);
        }
        f.generate_udev_rules;
    } catch (Exception e) {
        stderr.writeln(e);
    }
}
