extends "res://scripts/game_world.gd"
## Game: inventory, trading and trade goods, jobs, notes, XP and perks.


# ------------------------------------------------------------------ inventory
func inv_count(id: String) -> int:
	for it in inventory:
		if it.id == id: return it.n
	return 0


func inv_add(id: String, n: int = 1) -> void:
	if id == "": return
	for it in inventory:
		if it.id == id:
			it.n += n
			return
	inventory.append({"id": id, "n": n})


func inv_take(id: String, n: int = 1) -> bool:
	for it in inventory:
		if it.id == id and it.n >= n:
			it.n -= n
			if it.n <= 0: inventory.erase(it)
			return true
	return false


func armor_total() -> int:
	var a := 0
	for slot in ["head", "body"]:
		if equip[slot] != "": a += Items.info(equip[slot]).get("armor", 0)
	return a


func gun_info() -> Dictionary:
	return Items.info(equip.gun) if equip.gun != "" else {}


func equip_item(id: String) -> void:
	var slot: String = Items.info(id).slot
	if slot in ["gun", "melee", "head", "body"]:
		equip[slot] = id
		hud.toast("Equipped %s." % Items.iname(id))
		_refresh_gun()
	open_inventory()


func use_item(id: String) -> void:
	var d := Items.info(id)
	if d.get("heal", 0) > 0 and player.hp < player.max_hp and inv_take(id):
		var hl: float = d.heal * ((1.0 + 0.5 * perk("medic")) if id == "medkit" else float(origin().get("food", 1.0)) * (1.0 + 0.5 * perk("lead_belly")))
		audio.play("heal" if id == "medkit" else "eat", Vector2.INF, -4.0)
		player.hp = minf(player.max_hp, player.hp + hl)
		add_text(player.wpos, "+%d hp" % int(hl), Color("9fd08a"))
	if hud.menu_open() or invs.visible: open_inventory()


func quick_heal() -> void:
	if player.hp >= player.max_hp: return
	if inv_count("medkit") > 0 and player.max_hp - player.hp >= 8: use_item("medkit")
	elif inv_count("food") > 0: use_item("food")
	elif inv_count("medkit") > 0: use_item("medkit")
	else: hud.toast("Nothing to heal with. Look for food and med kits.")


func _refresh_gun() -> void:
	var g := gun_info()
	player.gun_len = g.get("len", 6) if not g.is_empty() else 0


func open_inventory() -> void:
	if state != "play": return
	audio.play("pipboy", Vector2.INF, -6.0, 0.0)
	if invs.visible: invs.refresh()
	else: invs.open()


func unequip(slot: String) -> void:
	equip[slot] = "fists" if slot == "melee" else ""
	_refresh_gun()
	open_inventory()


## Drop one of an item on the ground as a bag you can pick back up.
func drop_item(id: String) -> void:
	var slot: String = Items.info(id).get("slot", "")
	if slot in ["gun", "melee", "head", "body"] and equip[slot] == id and inv_count(id) <= 1:
		unequip(slot)
	if not inv_take(id): return
	var cr := World.Crate.new()
	cr.pos = player.wpos + Vector2(0.4, 0.4)
	cr.kind = "bag"
	cr.fl = player.fl
	cr.set_meta("loot", [[id, 1]])
	_place_crate(cr)
	hud.toast("Dropped %s." % Items.iname(id))
	open_inventory()


func _reduction() -> float:
	return minf(0.6, armor_total() * 0.07)


func _buy(npc: Npc, id: String, n: int, cost: int) -> void:
	if _pay(cost): inv_add(id, n)
	open_trade(npc)


func _buy_stock(npc: Npc, i: int, cost: int) -> void:
	var stock: Array = npc.get_meta("stock")
	if _pay(cost):
		inv_add(stock[i])
		stock[i] = ""
	open_trade(npc)


func _sell(npc: Npc, id: String, val: int) -> void:
	if inv_take(id): player.carry.scrap += val
	open_trade(npc)


func _scrap_total() -> int:
	return player.carry.scrap + stash.scrap


func _pay(n: int) -> bool:
	if _scrap_total() < n: return false
	var from_carry := mini(n, player.carry.scrap)
	player.carry.scrap -= from_carry
	stash.scrap -= n - from_carry
	return true


func open_trade(npc: Npc) -> void:
	var fence := npc.has_meta("fence")
	if origin().get("raider", false) and not fence:
		var small: bool = npc.settlement < 0 or (npc.settlement < world.settlements.size() and world.settlements[npc.settlement].small)
		if small:
			add_text(npc.wpos + Vector2(0, -0.2), ["Not trading with raiders. Move along.", "I know that look. Get lost.", "We've got nothing for your kind."][randi() % 3], Color("e8a090"), 2.6)
			return
	if not npc.has_meta("stock"):
		var stock := []
		for t in (5 if fence else 3):
			stock.append(Items.gear_of_tier(rng.randi_range(2, 3) if fence else rng.randi_range(1, 3), rng))
		npc.set_meta("stock", stock)
	var stock: Array = npc.get_meta("stock")
	var lines := ["You have %d scrap (carried %d + stash %d)." % [_scrap_total(), player.carry.scrap, stash.scrap], "Buy:"]
	var btns := []
	for e in SHOP:
		var id: String = e[0]
		var n: int = e[1]
		var cost: int = e[2]
		cost = maxi(1, int(round(cost * (1.0 if npc.has_meta("fence") else float(origin().get("buy", 1.0))))))
		btns.append(["Buy %s ×%d — %d scrap" % [Items.iname(id), n, cost], func(): _buy(npc, id, n, cost), _scrap_total() < cost])
	for i in stock.size():
		var id: String = stock[i]
		if id == "": continue
		var cost: int = maxi(1, int(round(Items.info(id).value * (1.0 if npc.has_meta("fence") else float(origin().get("buy", 1.0))))))
		var ii := i
		btns.append(["Buy %s — %d scrap" % [Items.iname(id), cost], func(): _buy_stock(npc, ii, cost), _scrap_total() < cost])
	for it in inventory:
		var d := Items.info(it.id)
		if d.get("slot", "") in ["gun", "melee", "head", "body"] and it.id != equip[d.slot]:
			var id: String = it.id
			var val: int = maxi(1, int(d.value / 2.0 * (1.25 if npc.has_meta("fence") else float(origin().get("sell", 1.0)))))
			btns.append(["Sell %s — +%d scrap" % [d.name, val], func(): _sell(npc, id, val), false])
	if npc.settlement >= 0 and npc.settlement < world.settlements.size():
		btns.insert(0, ["Trade goods (water, salt, glass…) »", func(): open_goods(npc), false])
		if not world.settlements[npc.settlement].small:
			btns.insert(1, ["Jobs »", func(): open_jobs(npc), false])
	btns.append(["Leave", hud.hide_menu, false])
	hud.show_menu("The fence" if fence else ("Trader" if npc.type == "trader" else "Travelling merchant"), lines, btns)


func goods_carried() -> int:
	var n := 0
	for it in inventory:
		if Items.info(it.id).get("trade", false): n += it.n
	return n


func goods_cap() -> int:
	return 30 + int(origin().get("cap", 0)) + (10 if any_up("tent") else 0) + 15 * perk("strong_back")


## Commodity trading: this town's prices, buy 1 / 5, sell 1 / all.
func open_goods(npc: Npc) -> void:
	var st: World.Settlement = world.settlements[npc.settlement]
	var m := Economy.market(world, npc.settlement)
	var lines := ["%s market. You have %d scrap. Hauling %d / %d trade goods." % [st.name, _scrap_total(), goods_carried(), goods_cap()]]
	var pm: float = float(origin().get("buy", 1.0)) * (1.0 - 0.08 * perk("barter"))
	var sm: float = float(origin().get("sell", 1.0)) * (1.0 + 0.08 * perk("barter"))
	var btns := []
	for gd in m:
		var e: Dictionary = m[gd]
		var have := inv_count(gd)
		var buy := maxi(1, int(round(e.buy * pm)))
		var sell := maxi(1, int(round(e.sell * sm)))
		var tag := " (local, cheap)" if e.made else (" (in demand)" if e.wanted else "")
		lines.append("%s%s — buy %d · sell %d · you have %d" % [Items.iname(gd), tag, buy, sell, have])
		var id: String = gd
		if e.stock:
			var room := goods_cap() - goods_carried()
			btns.append(["Buy %s — %d" % [Items.iname(gd), buy], func(): _buy_good(npc, id, 1, buy), _scrap_total() < buy or room < 1])
			btns.append(["Buy 5 %s — %d" % [Items.iname(gd), buy * 5], func(): _buy_good(npc, id, 5, buy), _scrap_total() < buy * 5 or room < 5])
		if have > 0:
			btns.append(["Sell %s — +%d" % [Items.iname(gd), sell], func(): _sell_good(npc, id, 1, sell), false])
			if have > 1: btns.append(["Sell all %d %s — +%d" % [have, Items.iname(gd), sell * have], func(): _sell_good(npc, id, have, sell), false])
	btns.append(["« Back", func(): open_trade(npc), false])
	btns.append(["Leave", hud.hide_menu, false])
	hud.show_menu("Trade goods", lines, btns)


func _buy_good(npc: Npc, id: String, n: int, each: int) -> void:
	if goods_carried() + n <= goods_cap() and _pay(each * n):
		inv_add(id, n)
		audio.play("coins", Vector2.INF, -6.0)
	open_goods(npc)


func _sell_good(npc: Npc, id: String, n: int, each: int) -> void:
	if inv_take(id, n):
		player.carry.scrap += each * n
		add_text(player.wpos, "+%d scrap" % (each * n), Color("f2e27a"))
		audio.play("coins", Vector2.INF, -6.0)
		if each > Items.info(id).value: gain_xp(maxi(1, (each - Items.info(id).value) * n / 2), "")
	open_goods(npc)


# ------------------------------------------------------------------ jobs and cleared sites
func _check_cleared(loc_id: String) -> void:
	var l := world.loc_by_id(loc_id)
	if l.is_empty() or l.get("cleared", false): return
	for s in world.spawns:
		if s.get("loc", "") == loc_id and not s.get("dead", false): return
	l.cleared = true
	world.cleared[loc_id] = true
	hud.show_card("%s\nCLEARED" % l.name.to_upper())
	audio.play("discover", Vector2.INF, -3.0, 0.0)
	gain_xp(80, "")
	for j in jobs:
		if j.kind == "clear" and j.loc == loc_id: _complete_job(j)


func _complete_job(j: Dictionary) -> void:
	if j.get("done", false): return
	j.done = true
	stash.scrap += int(j.reward)
	audio.play("coins", Vector2.INF, -3.0)
	hud.toast("Job done: %s. +%d scrap (in your stash), +%d XP." % [j.title, j.reward, j.xp])
	gain_xp(int(j.xp), "")
	jobs.erase(j)


func open_jobs(npc: Npc) -> void:
	var si := npc.settlement
	var lines := ["Active jobs: %d / 3" % jobs.size()]
	var btns := []
	for j in jobs:
		lines.append("• %s (from %s)" % [j.title, j.from])
		if j.kind == "deliver" and world.settlements[si].id == j.loc:
			var jj = j
			btns.append(["Hand over the package — +%d" % j.reward, func(): _complete_job(jj); open_jobs(npc), false])
		if j.kind == "supply" and j.si == si:
			var jj = j
			btns.append(["Hand over %d %s — +%d" % [j.n, Items.iname(j.good), j.reward], func():
				if inv_take(jj.good, jj.n): _complete_job(jj)
				open_jobs(npc), inv_count(j.good) < j.n])
	if not npc.has_meta("job") or float(npc.get_meta("job_t", -999.0)) < time - 300.0:
		npc.set_meta("job", Jobs.offer(self, si))
		npc.set_meta("job_t", time)
	var off: Dictionary = npc.get_meta("job")
	if not off.is_empty() and not off.get("taken", false):
		lines.append("")
		lines.append("OFFER: %s" % off.title)
		lines.append(off.desc)
		lines.append("Pays %d scrap, %d XP." % [off.reward, off.xp])
		btns.append(["Take the job", func():
			off.taken = true
			jobs.append(off)
			audio.play("pipboy", Vector2.INF, -6.0, 0.0)
			hud.toast("Job taken: %s. It's on your compass and map." % off.title)
			open_jobs(npc), jobs.size() >= 3])
	btns.append(["« Back", func(): open_trade(npc), false])
	hud.show_menu("Jobs board", lines, btns)


func _update_jobs() -> void:
	for j in jobs:
		if j.kind == "bounty" and not j.get("spawned", false) and player.wpos.distance_to(j.target) < 45.0:
			j.spawned = true
			var at: Vector2 = j.target
			var ck := World.chunk_of(at)
			world.ensure_ready(ck.x, ck.y)
			for t in 30:
				if world.can_stand(at, 0.4, 0) and world.building_at(at.x, at.y) == 0: break
				at += Vector2(randf_range(-3, 3), randf_range(-3, 3))
			var key := World.ckey(ck.x, ck.y)
			for k in 4:
				var sp := {"type": "raider", "pos": at + Vector2.from_angle(k * 1.6) * (0.0 if k == 0 else 2.0), "home": at, "home_r": 4.0, "chunk": key}
				var e := _spawn_enemy(sp)
				if k == 0:
					e.set_meta("boss", j.boss)
					e.hp *= 6.0
					e.max_hp = e.hp
					e.weapon = "smg"
			hud.toast("You've found %s's camp." % j.boss)


func _find_note() -> void:
	var unread := []
	for i in Lore.NOTES.size():
		if i not in notes_read: unread.append(i)
	if unread.is_empty(): return
	var i: int = unread[randi() % unread.size()]
	notes_read.append(i)
	gain_xp(5, "")
	show_note(i)


func show_note(i: int) -> void:
	var n: Array = Lore.NOTES[i]
	audio.play("pickup", Vector2.INF, -6.0)
	hud.show_menu(n[0], [n[1]], [["Keep it  (notes are in your inventory)", hud.hide_menu, false]])


func show_stats() -> void:
	var lines := ["%s · Level %d · %d / %d XP to next" % [origin().name, level, xp, Perks.xp_needed(level)],
		"Kills %d · Places found %d / %d · Sites cleared %d · Notes %d / %d" % [player.kills, world.discovered.size(), world.locs.size(), world.cleared.size(), notes_read.size(), Lore.NOTES.size()],
		"Camps %d · Stash: %d scrap, %d cloth, %d wood" % [camps.size(), stash.scrap, stash.cloth, stash.wood], "", "PERKS:"]
	if perks.is_empty(): lines.append("None yet — level up to choose one.")
	for k in perks:
		lines.append("%s %d/%d — %s" % [Perks.LIST[k].name, perks[k], Perks.LIST[k].max, Perks.LIST[k].desc])
	if jobs.size():
		lines.append("")
		lines.append("JOBS:")
		for j in jobs: lines.append("• %s — %s" % [j.title, j.desc])
	hud.show_menu("Your story so far", lines, [["Close", hud.hide_menu, false]])


func show_notes() -> void:
	var btns := []
	for i in notes_read:
		var ii: int = i
		btns.append([Lore.NOTES[i][0], func(): show_note(ii), false])
	btns.append(["Close", hud.hide_menu, false])
	hud.show_menu("Notes & holotapes", ["You've found %d of %d." % [notes_read.size(), Lore.NOTES.size()]], btns)
