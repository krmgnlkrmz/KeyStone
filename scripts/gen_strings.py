#!/usr/bin/env python3
"""Generates App/Resources/Localizable.xcstrings, App/Resources/InfoPlist.xcstrings and
Widget/Localizable.xcstrings from the copy table below (English base, Turkish second).

The table follows the design system's copy deck; Turkish runs ~25 % longer, the UI allows for it.
Tone: calm and factual, no blame, no exclamation marks.

Plural handling: an entry may give {"en": {"one": ..., "other": ...}} for a single integer argument,
or a substitution spec (see `sub`) when the plural argument is one of several.
Run: python3 scripts/gen_strings.py   (then scripts/check_strings.py verifies coverage)
"""
import json, os

ROOT = os.path.join(os.path.dirname(__file__), "..")

def sub(template, name, arg, one, other):
    """English plural substitution for one of several arguments."""
    return {"template": template, "name": name, "arg": arg, "one": one, "other": other}

S = {
    # App / onboarding
    "app.name": ("Keystone", "Denge Noktası"),
    "splash.tagline": ("A STRUCTURAL PUZZLE", "BİR YAPI BULMACASI"),
    "consent.waiting": ("Waiting for your privacy choices", "Gizlilik tercihlerin bekleniyor"),
    "att.title": ("Before iOS asks", "iOS sormadan önce"),
    "att.body1": ("Ads keep Keystone free. iOS will ask if they can be more relevant to you.",
                  "Reklamlar Denge Noktası'nı ücretsiz tutar. iOS, reklamların sana daha uygun olup olamayacağını soracak."),
    "att.body2": ("Either answer is fine. The game stays the same.", "İki cevap da olur. Oyun aynı kalır."),
    "common.continue": ("Continue", "Devam"),
    "common.cancel": ("Cancel", "Vazgeç"),
    "common.done": ("Done", "Bitti"),
    "common.backToMap": ("Back to Map", "Haritaya Dön"),
    "common.backToMenu": ("Back to Menu", "Menüye Dön"),

    # Menu
    "menu.tagline": ("Remove pieces. Keep it standing.", "Parçaları sök. Yapı ayakta kalsın."),
    "menu.continue": ("CONTINUE", "DEVAM ET"),
    "menu.start": ("START", "BAŞLA"),
    "menu.noLevels": ("No levels found", "Bölüm bulunamadı"),
    "menu.levels": ("Levels", "Bölümler"),
    "menu.daily": ("Daily Level", "Günlük Bölüm"),
    "menu.daily.value %@ %lld": ("%1$@ · %2$lld-day streak", "%1$@ · %2$lld günlük seri"),
    "menu.daily.solved %lld": ("Solved · %lld-day streak", "Çözüldü · %lld günlük seri"),
    "menu.endless": ("Endless", "Sonsuz Mod"),
    "menu.endless.value": ("Verified", "Doğrulanmış"),
    "menu.settings": ("Settings", "Ayarlar"),
    "menu.sound": ("Sound", "Ses"),
    "menu.gameCenter": ("Achievements", "Başarımlar"),
    "menu.gameCenter.off": ("Sign in to Game Center in Settings to see achievements.", "Başarımları görmek için Ayarlar'dan Game Center'a giriş yap."),

    # Map
    "map.title": ("Levels", "Bölümler"),
    "map.progress %lld %lld": ("%1$lld / %2$lld levels", "%1$lld / %2$lld bölüm"),
    "map.removeAds": ("Remove Ads", "Reklamları Kaldır"),
    "map.play": ("PLAY", "OYNA"),
    "map.zoneLocked %lld": ({"one": "Opens after %lld more level", "other": "Opens after %lld more levels"},
                            "%lld bölüm daha bitince açılır"),
    "map.zoneLockedSub %@": ("Finish 70 %% of %@ to see these structures.", "Bu yapıları görmek için %@ bölgesinin %%70'ini bitir."),
    "map.lockedToast": ("Finish more of the previous region first.", "Önce önceki bölgede biraz daha ilerle."),
    "zone.woodScaffold": ("Wooden Scaffold", "Ahşap İskele"),
    "zone.stoneArch": ("Stone Arch", "Taş Kemer"),
    "zone.ironTruss": ("Iron Truss", "Demir Kafes"),
    "zone.ropeBridge": ("Rope Bridge", "Halat Köprü"),
    "zone.steelCrane": ("Steel Crane", "Çelik Vinç"),
    "zone.counterweight": ("Counterweight", "Karşı Ağırlık"),
    "zone.keystone": ("Keystone", "Kilit Taşı"),
    "level.title %lld %@": ("Level %1$lld · %2$@", "Bölüm %1$lld · %2$@"),
    "level.short %lld": ("Level %lld", "Bölüm %lld"),
    "level.untitled": ("Structure", "Yapı"),

    # HUD
    "hud.level %lld": ("LEVEL %lld", "BÖLÜM %lld"),
    "hud.daily %@": ("DAILY · %@", "GÜNLÜK · %@"),
    "hud.endless %lld": ("ENDLESS · %lld", "SONSUZ · %lld"),
    "hud.moves": ("MOVES", "HAMLE"),
    "hud.done %lld %lld": ("%1$lld/%2$lld DONE", "%1$lld/%2$lld TAMAM"),
    "hud.undo": ("Undo", "Geri Al"),
    "hud.support": ("Support", "Destek"),
    "hud.placing": ("Placing…", "Yerleştiriliyor…"),
    "hud.hint": ("Hint", "İpucu"),
    "hud.settling": ("The structure is settling", "Yapı oturuyor"),
    "demo.chip": ("Perfect solution", "Mükemmel çözüm"),

    # Goals
    "goal.remove %lld %@": ("Remove %1$lld %2$@. Keep it standing.", "%1$lld %2$@ sök. Yapı ayakta kalsın."),
    "goal.removeOne %@": ("Remove the %@. Keep it standing.", "%@ sök. Yapı ayakta kalsın."),
    "goal.support %lld %@": ("Place the support, then remove %1$lld %2$@.", "Desteği yerleştir, sonra %1$lld %2$@ sök."),
    "goal.drop %@": ("Drop only the %@.", "Yalnızca %@ düşür."),

    # Nouns: nominative (callouts), object forms (goals: EN singular/plural, TR accusative)
    "noun.post": ("post", "direk"), "noun.post.objectOne": ("post", "direği"), "noun.post.objectMany": ("posts", "direği"),
    "noun.beam": ("beam", "kiriş"), "noun.beam.objectOne": ("beam", "kirişi"), "noun.beam.objectMany": ("beams", "kirişi"),
    "noun.block": ("block", "blok"), "noun.block.objectOne": ("block", "bloğu"), "noun.block.objectMany": ("blocks", "bloğu"),
    "noun.column": ("column", "kolon"), "noun.column.objectOne": ("column", "kolonu"), "noun.column.objectMany": ("columns", "kolonu"),
    "noun.girder": ("girder", "putrel"), "noun.girder.objectOne": ("girder", "putreli"), "noun.girder.objectMany": ("girders", "putreli"),
    "noun.keystone": ("keystone", "kilit taşı"), "noun.keystone.objectOne": ("keystone", "kilit taşını"), "noun.keystone.objectMany": ("keystones", "kilit taşını"),
    "noun.support": ("support", "destek"), "noun.support.objectOne": ("support", "desteği"), "noun.support.objectMany": ("supports", "desteği"),
    "noun.rope": ("rope", "halat"), "noun.rope.objectOne": ("rope", "halatı"), "noun.rope.objectMany": ("ropes", "halatı"),
    "noun.piece": ("piece", "parça"), "noun.piece.objectOne": ("marked piece", "işaretli parçayı"), "noun.piece.objectMany": ("marked pieces", "işaretli parçayı"),

    # Materials, tension (VoiceOver)
    "material.wood": ("wood", "ahşap"), "material.stone": ("stone", "taş"), "material.steel": ("steel", "çelik"),
    "material.brass": ("brass", "pirinç"), "material.rope": ("rope", "halat"),
    "tension.light": ("light load", "hafif yük"), "tension.tense": ("under load", "yük altında"),
    "tension.critical": ("critical load", "kritik yük"),
    "a11y.removable": ("removable", "sökülebilir"), "a11y.fixed": ("fixed", "sabit"),
    "a11y.notRemovable": ("can't be removed", "sökülemez"), "a11y.selected": ("selected", "seçili"),
    "a11y.target": ("goal piece", "hedef parça"),
    "a11y.hint.select": ("Double-tap to select.", "Seçmek için iki kez dokun."),
    "a11y.hint.remove": ("Double-tap again to remove.", "Sökmek için tekrar iki kez dokun."),
    "a11y.moves %lld %lld": ("%1$lld of %2$lld moves", "%2$lld hamleden %1$lld"),
    "a11y.stars %lld": ({"one": "%lld star", "other": "%lld stars"}, "%lld yıldız"),
    "a11y.locked": ("locked", "kilitli"),
    "a11y.notPlayed": ("not played yet", "henüz oynanmadı"),
    "a11y.support.hint": ("Drag into the play area to place a support.", "Destek koymak için oyun alanına sürükle."),
    "a11y.support.placeBest": ("Place support", "Desteği yerleştir"),

    # Tutorial
    "tut.1": ("Tap a piece, then tap it again to remove it.", "Bir parçaya dokun, sökmek için tekrar dokun."),
    "tut.2": ("Remove a load-bearing piece and it falls.", "Yük taşıyan parçayı sökersen yapı çöker."),
    "tut.3": ("Drag the support into place.", "Desteği sürükleyerek yerleştir."),
    "tut.skip": ("Skip", "Atla"),

    # Support
    "support.fits": ("Fits here", "Buraya uyar"),
    "support.invalid": ("Won't fit", "Buraya olmaz"),
    "support.here": ("Support here", "Destek buraya"),
    "support.toast.invalid": ("Won't fit there. Place it under a piece.", "Oraya sığmaz. Bir parçanın altına yerleştir."),

    # Toasts
    "toast.keystone": ("The keystone can't be removed.", "Kilit taşı sökülemez."),
    "toast.support": ("Supports stay once placed.", "Destek bir kez konunca kalır."),
    "toast.fixed": ("Fixed piece. It can't be removed.", "Sabit parça. Sökülemez."),

    # Collapse
    "collapse.kicker": ("COLLAPSE REPLAY", "ÇÖKME TEKRARI"),
    "collapse.title": ("It collapsed", "Yapı çöktü"),
    "collapse.title.drop": ("Too much fell", "Fazlası düştü"),
    "collapse.sub": ("Watch which piece gave way.", "Hangi parçanın dayanamadığını izle."),
    "collapse.label.load %@": ("This %@ couldn't carry the load.", "Bu %@ yükü taşıyamadı."),
    "collapse.label.balance %@": ("This %@ lost its balance.", "Bu %@ dengesini kaybetti."),
    "collapse.a11y %@": ("Collapse replay. %@", "Çökme tekrarı. %@"),
    "collapse.retry": ("Retry", "Tekrar Dene"),
    "collapse.lastMove": ("Back to last move", "Son hamleye dön"),
    "collapse.rm": ("Reduce Motion: still frames, no shake.", "Hareketi Azalt: sabit kareler, sarsıntı yok."),
    "collapse.still.before": ("Before", "Önce"),
    "collapse.still.move %lld": ("Move %lld", "Hamle %lld"),
    "collapse.still.collapse": ("Collapse", "Çökme"),
    "replay.play": ("Play replay", "Tekrarı oynat"),
    "replay.pause": ("Pause replay", "Tekrarı duraklat"),
    "replay.position": ("Replay position", "Tekrar konumu"),
    "replay.time %@": ("%@ seconds", "%@ saniye"),
    "replay.move %lld": ("move %lld", "hamle %lld"),

    # Out of moves
    "outOfMoves.kicker": ("STILL STANDING · GOAL NOT MET", "HÂLÂ AYAKTA · HEDEF TAMAMLANMADI"),
    "outOfMoves.title": ("Out of moves", "Hamle kalmadı"),
    "outOfMoves.body %lld %lld": ("%1$lld of %2$lld done. Undo a move or start fresh.", "%2$lld hedeften %1$lld tamam. Bir hamleyi geri al ya da baştan başla."),
    "outOfMoves.body.drop": ("The target is still up. Undo, or start fresh.", "Hedef hâlâ yerinde. Geri al ya da baştan başla."),
    "outOfMoves.undo": ("Undo last move", "Son hamleyi geri al"),

    # Success
    "success.kicker %lld": ("LEVEL %lld CLEARED", "BÖLÜM %lld TAMAM"),
    "success.kicker.daily": ("DAILY LEVEL SOLVED", "GÜNLÜK BÖLÜM ÇÖZÜLDÜ"),
    "success.kicker.endless": ("ENDLESS LEVEL CLEARED", "SONSUZ BÖLÜM TAMAM"),
    "success.title": ("Still standing", "Hâlâ ayakta"),
    "success.title.drop": ("Clean drop", "Temiz düşüş"),
    "success.moves %lld %lld": (sub("Solved in %#@moves@ · best %2$lld", "moves", 1, "%arg move", "%arg moves"),
                                "%1$lld hamlede çözdün · en iyi %2$lld"),
    "success.newBest": ("New best", "Yeni rekor"),
    "success.next": ("Next Level", "Sonraki Bölüm"),
    "success.nextEndless": ("Next Endless Level", "Sonraki Sonsuz Bölüm"),
    "success.perfect": ("See the perfect solution", "Mükemmel çözümü gör"),
    "success.replay": ("Replay", "Tekrar Oyna"),
    "success.map": ("Map", "Harita"),
    "success.menu": ("Menu", "Menü"),

    # Pause
    "pause.title": ("Paused", "Duraklatıldı"),
    "pause.sub %@ %lld %lld": ("%1$@ · %2$lld / %3$lld moves", "%1$@ · %2$lld / %3$lld hamle"),
    "pause.resume": ("Resume", "Devam Et"),
    "pause.restart": ("Restart Level", "Baştan Başla"),
    "pause.hint": ("Hint: show the critical piece", "İpucu: kritik parçayı göster"),
    "pause.sound": ("Sound", "Ses"),
    "pause.haptics": ("Haptics", "Haptik"),

    # Hints
    "hint.title": ("Show the critical piece?", "Kritik parçayı gösterelim mi?"),
    "hint.body": ("We'll mark the critical piece for 5 seconds. Watch a short ad first.",
                  "Kritik parçayı 5 saniye işaretleyeceğiz. Önce kısa bir reklam izle."),
    "hint.body.free": ("We'll mark the critical piece for 5 seconds. Free, because you removed ads.",
                       "Kritik parçayı 5 saniye işaretleyeceğiz. Reklamları kaldırdığın için ücretsiz."),
    "hint.watch": ("Watch Ad", "Reklamı İzle"),
    "hint.adLength": ("AD · ~15 S", "REKLAM · ~15 SN"),
    "hint.notNow": ("Not now", "Vazgeç"),
    "hint.optional": ("Hints are optional. Every level can be solved without one.", "İpuçları isteğe bağlı. Her bölüm ipucusuz çözülebilir."),
    "hint.active": ("Critical piece", "Kritik parça"),
    "hint.active.support": ("Place the support", "Desteği yerleştir"),
    "hint.seconds %lld": ("%lld s", "%lld sn"),
    "hint.noAd.title": ("No ad available right now", "Şu an reklam yok"),
    "hint.noAd.body": ("The hint is free for this level.", "İpucu bu bölüm için ücretsiz."),
    "hint.show": ("Show Hint", "İpucunu Göster"),
    "hint.noSolution": ("No solution from here. Undo a move first.", "Buradan çözüm yok. Önce bir hamleyi geri al."),
    "hint.unavailable": ("Hints aren't available for this level.", "Bu bölümde ipucu yok."),
    "hint.notEarned": ("The ad closed early, so the hint stays hidden.", "Reklam erken kapandı, ipucu gizli kaldı."),
    "hint.offline.toast": ("Offline. Hints need an ad connection.", "Çevrimdışı. İpucu için reklam bağlantısı gerekir."),

    # Ads
    "ad.tag": ("AD", "REKLAM"),
    "ad.offline.tag": ("OFFLINE", "ÇEVRİMDIŞI"),
    "ad.offline": ("Offline · ads unavailable", "Çevrimdışı · reklam yok"),
    "ad.slot": ("AD", "REKLAM"),
    "ad.slot.offline": ("AD · OFFLINE", "REKLAM · ÇEVRİMDIŞI"),

    # Store
    "store.thanks": ("Ads removed. Thank you.", "Reklamlar kaldırıldı. Teşekkürler."),
    "store.price %@": ("Removes banners and interstitials for %@.", "Banner ve geçiş reklamlarını %@ karşılığında kaldırır."),
    "store.priceUnknown": ("Removes banners and interstitials.", "Banner ve geçiş reklamlarını kaldırır."),

    # Settings
    "settings.title": ("Settings", "Ayarlar"),
    "settings.game": ("Game", "Oyun"),
    "settings.appearance": ("Appearance", "Görünüm"),
    "settings.appearance.system": ("System", "Sistem"),
    "settings.appearance.light": ("Light", "Açık"),
    "settings.appearance.dark": ("Dark", "Koyu"),
    "settings.sound": ("Sound", "Ses"),
    "settings.music": ("Music", "Müzik"),
    "settings.haptics": ("Haptics", "Haptik"),
    "settings.leftHand": ("Left-Hand Mode", "Sol El Modu"),
    "settings.leftHand.footer": ("Left-Hand Mode moves Undo and Support to the left.", "Sol El Modu, Geri Al ve Destek'i sola taşır."),
    "settings.reduceMotion": ("Reduce Motion · Follows iOS", "Hareketi Azalt · iOS'a uyar"),
    "settings.on": ("On", "Açık"),
    "settings.off": ("Off", "Kapalı"),
    "settings.purchases": ("Purchases", "Satın Almalar"),
    "settings.removeAds": ("Remove Ads", "Reklamları Kaldır"),
    "settings.adsRemoved": ("Ads Removed", "Reklamlar Kaldırıldı"),
    "settings.purchased": ("Purchased", "Satın alındı"),
    "settings.restore": ("Restore Purchases", "Satın Almaları Geri Yükle"),
    "settings.restored": ("Purchases restored.", "Satın almalar geri yüklendi."),
    "settings.nothingToRestore": ("No purchases to restore.", "Geri yüklenecek satın alma yok."),
    "settings.pending": ("Pending approval", "Onay bekleniyor"),
    "settings.pending.footer": ("Waiting for Ask to Buy. Ads stay on until it's approved.", "Satın Alma İzni bekleniyor. Onaylanana kadar reklamlar açık kalır."),
    "settings.failed": ("The purchase didn't go through. You weren't charged.", "Satın alma tamamlanmadı. Ücret alınmadı."),
    "settings.privacy": ("Privacy", "Gizlilik"),
    "settings.privacySettings": ("Privacy settings", "Gizlilik ayarları"),
    "settings.privacyPolicy": ("Privacy Policy", "Gizlilik Politikası"),
    "settings.privacyPolicy.missing": ("The privacy policy address isn't set in this build.", "Bu sürümde gizlilik politikası adresi tanımlı değil."),
    "settings.playerData": ("Player Data", "Oyuncu Verisi"),
    "settings.reset": ("Reset Progress…", "İlerlemeyi Sıfırla…"),
    "settings.reset.done": ("Progress reset.", "İlerleme sıfırlandı."),
    "settings.about": ("About", "Hakkında"),
    "settings.version": ("Version", "Sürüm"),
    "settings.support": ("Contact Support", "Destekle İletişim"),
    "reset.alert.title": ("Reset all progress?", "Tüm ilerleme sıfırlansın mı?"),
    "reset.alert.body": ("Stars and levels on this device will be deleted.", "Bu cihazdaki yıldızlar ve bölümler silinecek."),
    "reset.alert.confirm": ("Reset", "Sıfırla"),

    # Daily
    "daily.title": ("Daily Level", "Günlük Bölüm"),
    "daily.short": ("Daily", "Günlük"),
    "daily.done": ("Done", "Bitti"),
    "daily.streak %lld": ("%lld-day streak", "%lld günlük seri"),
    "daily.solved": ("Solved today", "Bugün çözüldü"),
    "daily.notSolved": ("Not solved today", "Bugün çözülmedi"),
    "daily.play %lld": ({"one": "Play · par %lld move", "other": "Play · par %lld moves"}, "Oyna · hedef %lld hamle"),
    "daily.playAgain": ("Play again", "Tekrar oyna"),
    "daily.footer": ("A new structure every day at midnight.", "Her gece yarısı yeni bir yapı."),

    # Endless (truthful: offline-verified pool, not generated on device)
    "endless.title": ("Endless", "Sonsuz Mod"),
    "endless.levelTitle %lld": ("Endless · %lld", "Sonsuz · %lld"),
    "endless.building %lld": ("Loading level %lld", "Bölüm %lld yükleniyor"),
    "endless.body": ("Every endless level was checked for a solution before it shipped. They all work offline, and there is no last level.",
                     "Her sonsuz bölümün çözülebildiği önceden doğrulandı. Hepsi çevrimdışı çalışır ve son bölüm yok."),
}

WIDGET = {
    "widget.name": ("Daily Level", "Günlük Bölüm"),
    "widget.description": ("Today's structure and your streak.", "Bugünün yapısı ve serin."),
    "widget.daily": ("DAILY", "GÜNLÜK"),
    "widget.days": ("days", "gün"),
    "widget.solved": ("Solved", "Çözüldü"),
    "widget.notSolved": ("Not solved", "Çözülmedi"),
    "widget.par %lld": ({"one": "Par %lld move", "other": "Par %lld moves"}, "Hedef %lld hamle"),
}

INFOPLIST = {
    "CFBundleDisplayName": ("Keystone", "Denge Noktası"),
    "NSUserTrackingUsageDescription": (
        "Used to make ads more relevant to you. If you don't allow it, the whole game stays open.",
        "Reklamların sana daha uygun olması için kullanılır. İzin vermesen de oyunun tamamı açık kalır."),
}


def unit(v):
    return {"stringUnit": {"state": "translated", "value": v}}


def loc(value):
    if isinstance(value, dict) and "template" in value:
        return {
            "stringUnit": {"state": "translated", "value": value["template"]},
            "substitutions": {value["name"]: {
                "argNum": value["arg"], "formatSpecifier": "lld",
                "variations": {"plural": {"one": unit(value["one"]), "other": unit(value["other"])}},
            }},
        }
    if isinstance(value, dict):
        return {"variations": {"plural": {k: unit(v) for k, v in value.items()}}}
    return unit(value)


def catalog(table, comment_prefix=""):
    strings = {}
    for key in sorted(table):
        en, tr = table[key]
        strings[key] = {"extractionState": "manual", "localizations": {"en": loc(en), "tr": loc(tr)}}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def write(path, data):
    with open(os.path.join(ROOT, path), "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    write("App/Resources/Localizable.xcstrings", catalog(S))
    write("App/Resources/InfoPlist.xcstrings", catalog(INFOPLIST))
    write("Widget/Localizable.xcstrings", catalog(WIDGET))
    write("Widget/InfoPlist.xcstrings", catalog({"CFBundleDisplayName": INFOPLIST["CFBundleDisplayName"]}))
    print(f"{len(S)} app strings, {len(WIDGET)} widget strings")
