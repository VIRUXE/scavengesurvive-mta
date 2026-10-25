# exec'd in a live Blender after session.py, transplant.py, tp_strip.py, tp3.py and tp_tex.py: builds twins from
# tools/data/hatless_transplant.json. build(skin) leaves the result in the "work" object; review(skin, tag) renders it
# from ten angles into <work>/renders; export(skin) writes <name>_nohat.dff/.txd into <work>/export.
import json
import os

ns = bpy.app.driver_namespace  # noqa: F821 (exec'd inside Blender)
CONFIG = os.path.join(ns["REPO"], "tools", "data", "hatless_transplant.json")


def config():
    data = json.load(open(CONFIG))
    return {int(k): v for k, v in data.items()}


def build(skin):
    row = config()[skin]
    ns["donor_choice"] = ns.get("donor_choice") or {}
    ns["donor_choice"][skin] = row["donor"]
    rep = {"seam": ns["transplant3"](skin, donor=row["donor"], **row["seam"])}
    tex = {k: (tuple(v) if isinstance(v, list) else v) for k, v in row["texture"].items()}
    rep["texture"] = ns["tp_texture"](skin, **tex)
    return rep


def review(skin, tag="r-"):
    ns["preview"](up_min=-1.0)
    return ns["render_obj"]("preview", f"{tag}{skin}", modes=("tex", "grey"), res=220)


def export(skin):
    return ns["export2"](skin)


def build_all(skins=None, do_export=False, tag=None):
    out = {}
    for skin in skins or sorted(config()):
        rep = build(skin)
        if tag:
            review(skin, tag)
        if do_export:
            rep["file"] = export(skin)
        out[skin] = rep
    return out


ns.update(hatless_config=config, hatless_build=build, hatless_review=review, hatless_export=export, hatless_build_all=build_all)
