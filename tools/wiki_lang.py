"""The texts tools/wiki_tables.py writes into the wiki, in the languages other than English. Written by hand.

TEXTS[<code>] maps each English text of wiki_tables (headings, table headers, sentences with their %s/%d slots in the
same order) to its translation; a text missing here stays English, and wiki_tables lists the missing ones when it
runs. Item, calibre, liquid and supply drop names are not here: they come from the game's own strings_<code>.lua.
The Portuguese is European Portuguese, in the words the game uses (Bancada de trabalho, Sucata, Colete...).
"""
from __future__ import annotations

import re
from pathlib import Path

# the item tooltips wiki_tables.TOOLTIPS writes in place of lang_en.lua's, in Portuguese
PROX_MINE_PT = "Prime [F] para a plantar e armar: fica pronta 5 segundos depois e qualquer jogador que chegue a 6 m fá-la explodir"
TOOLTIPS_PT = {
    "Campfire": "Feita com 3 Toros de madeira e um Isqueiro (sem gasolina); segura comida e prime [F] junto à fogueira para a cozinhar",
    "TntProxMine": PROX_MINE_PT,
    "IedProxMine": PROX_MINE_PT,
    "EmpProxMine": PROX_MINE_PT,
    "PetrolBomb": "Prime [F] para a armar: uma carga incendiária que explode numa bola de fogo de 5 m ao fim de 5 segundos e não estraga itens",
    "Flashlight": "Segura-a na mão e prime [J] para a ligar ou desligar: o braço sobe e ela lança um feixe estreito em frente que ilumina paredes, chão e quem lá estiver, e todos à volta o veem. Com óculos postos, toca em [J] para a lanterna e mantém para os óculos",
}

# fmt: off
TEXTS = {
    "pt": {
        " (%d of them inside houses)": " (%d delas dentro de casas)",
        " (firearm)": " (arma de fogo)",
        " (kept)": " (fica)",
        " (melee)": " (corpo a corpo)",
        " A Refining Machine turns it into %s.": " Uma Máquina de refinação transforma-a em %s.",
        " and %d more": " e mais %d",
        "%d drop points": "%d pontos de entrega",
        "%d kept": "%d ficam",
        "%d used up": "%d gastos",
        "%s in %s": "%s em %s",
        "%s rounds": "%s balas",
        "%s spawn points: %s": "%s pontos de aparecimento: %s",
        "; also ": "; também ",
        "; taken down again with a %s in %s, which gives the parts back": "; desmonta-se com %s em %s, que devolve as peças",
        "A Water Purifier turns one holding Sea Water into one holding Water, see [Machines](Machines).": "Um Purificador de água transforma um com Água do mar num com Água, ver [Máquinas](Machines).",
        "Already built in the world: %d (%s).": "Já construídos no mundo: %d (%s).",
        "Ammunition": "Munições",
        "Armour": "Colete",
        "As loot it always lands as the wheel of one vehicle style, and a vehicle only takes the wheel of its own style: the Wheel column of [Vehicles](Vehicles) names it.": "Como saque aparece sempre como a roda de um estilo de veículo, e um veículo só leva a roda do seu estilo: a coluna Roda de [Veículos](Vehicles) diz qual é.",
        "At a [Workbench](Workbench) with a %s: %s": "Numa [Bancada de trabalho](Workbench), com %s: %s",
        "Bag": "Mochila",
        "Bag, worn on the back": "Mochila, às costas",
        "Bags": "Mochilas",
        "Base bleed rate": "Hemorragia de base",
        "Bites": "Dentadas",
        "Blast radius": "Raio da explosão",
        "Bleed x": "Hemorragia ×",
        "By hand: %s": "À mão: %s",
        "Calibre": "Calibre",
        "Can be cooked": "Pode ser cozinhada",
        "Can be moved after placing": "Pode ser movida depois de colocada",
        "Can hold": "Pode levar",
        "Cannot be scrapped: a Scrap Machine destroys it, see [Scrap](Scrap).": "Não dá sucata: uma Máquina de sucata destrói-o, ver [Sucata](Scrap).",
        "Capacity": "Capacidade",
        "Carried in both hands": "Levado com as duas mãos",
        "Category": "Categoria",
        "Charge": "Carga",
        "Container": "Contentor",
        "Containers": "Contentores",
        "Crafted, see below.": "Fabricado, ver abaixo.",
        "Crafting": "Fabrico",
        "Defence": "Defesa",
        "Drink": "Bebida",
        "EMP": "EMP",
        "Examples": "Exemplos",
        "Explosive": "Explosivo",
        "Fits": "Serve em",
        "Five items of each size; the [Item Catalogue](Item-Catalogue) lists every item with its size.": "Cinco itens de cada tamanho; o [Catálogo de itens](Item-Catalogue) lista todos os itens com o seu tamanho.",
        "Food": "Comida",
        "Food per bite": "Comida por dentada",
        "Found wherever a %s is listed as loot: %s of those finds are this wheel.": "Aparece onde quer que %s esteja na lista de saque: %s desses achados são esta roda.",
        "Fuel": "Combustível",
        "Fuel tank": "Depósito",
        "Goggles, over the eyes": "Óculos, sobre os olhos",
        "Group": "Grupo",
        "Hat": "Chapéu",
        "Hit points": "Pontos de vida",
        "Holster, on the back": "Coldre, às costas",
        "Holster, on the thigh": "Coldre, na coxa",
        "Incendiary": "Incendiária",
        "Infects when raw": "Infeta se crua",
        "Item": "Item",
        "Item size": "Tamanho do item",
        "Items": "Itens",
        "Kind": "Tipo",
        "Knockout x": "Desmaio ×",
        "Large": "Grande",
        "Lies at %s fixed spots in the world (GTA's own boxes, crates and bags), put back a while after it is taken.": "Está em %s sítios fixos do mundo (as caixas, caixotes e sacos do próprio GTA) e volta a aparecer algum tempo depois de levado.",
        "Long pick-up": "Apanhar demora",
        "Loot weight (Good / Bad)": "Peso de saque (intacta / danificada)",
        "Made by": "Feito com",
        "Made by the Refining Machine out of %s, see [Machines](Machines).": "Feito pela Máquina de refinação a partir de %s, ver [Máquinas](Machines).",
        "Made by the Scrap Machine out of anything with a scrap value, see [Scrap](Scrap).": "Feita pela Máquina de sucata a partir de tudo o que tenha valor de sucata, ver [Sucata](Scrap).",
        "Magazine": "Carregador",
        "Mask": "Máscara",
        "Medium": "Média",
        "Melee": "Corpo a corpo",
        "Motion": "Movimento",
        "Movable after placing": "Pode ser movida depois de colocada",
        "Muzzle velocity": "Velocidade à boca",
        "No recipe makes or uses it.": "Nenhuma receita o faz ou usa.",
        "Not found as loot.": "Não aparece como saque.",
        "On the ground with a %s, %s: %s": "No chão, com %s, %s: %s",
        "Other item": "Outro item",
        "Other items": "Outros itens",
        "Other items called %s: %s.": "Outros itens chamados %s: %s.",
        "Part set": "Conjunto",
        "Parts": "Peças",
        "Penetration": "Penetração",
        "Property": "Propriedade",
        "Proximity": "Proximidade",
        "Radio": "Rádio",
        "Reusable": "Reutilizável",
        "Rounds": "Balas",
        "Scrap": "Sucata",
        "See also": "Ver também",
        "Share of the table": "Parte da tabela",
        "Size": "Tamanho",
        "Slots": "Espaços",
        "Slots when worn": "Espaços quando vestida",
        "Small": "Pequena",
        "Source": "Origem",
        "Spare magazines": "Carregadores extra",
        "Spawn chance": "Probabilidade de aparecer",
        "Supply drop \"%s\"": "Entrega de abastecimentos \"%s\"",
        "Taken off a vehicle it fits with a %s.": "Tira-se de um veículo onde serve com %s.",
        "The only wheel these %d vehicle types take: %s.": "A única roda que estes %d tipos de veículo levam: %s.",
        "Timed": "Temporizador",
        "Transferable": "Transferível",
        "Trigger": "Detonador",
        "Trunk slots": "Espaços na mala",
        "Type": "Tipo",
        "Used in": "Usado em",
        "Value": "Valor",
        "Vehicle": "Veículo",
        "Vehicle trunks, %s": "Malas de veículos, %s",
        "Weapon": "Arma",
        "Weapons": "Armas",
        "Wear slot": "Onde se veste",
        "What a burst tyre comes off as, with a %s; fitted again, the tyre is still burst.": "É como sai um pneu furado, com %s; montada outra vez, o pneu continua furado.",
        "Wheel": "Roda",
        "Where": "Onde",
        "Where to find it": "Onde encontrar",
        "World loot, %s": "Saque do mundo, %s",
        "Worth %d %s in a Scrap Machine, see [Scrap](Scrap).": "Vale %d %s numa Máquina de sucata, ver [Sucata](Scrap).",
        "bag worn on the back": "mochila às costas",
        "container placed in the world": "contentor colocado no mundo",
        "no": "não",
        "nothing": "nada",
        "nowhere yet": "ainda em lado nenhum",
        "taking down %d kinds of built item (kept)": "desmontar %d tipos de item construído (fica)",
        "the tool, kept": "a ferramenta, fica",
        "the trunk of the %s": "a mala do %s",
        "the trunks of %d vehicle types (%s)": "as malas de %d tipos de veículo (%s)",
        "the weapon caches (%s)": "os esconderijos de armas (%s)",
        "yes": "sim",
        # loot table kinds (world_<kind>, vehicle_<kind>)
        "civilian": "civil",
        "glovebox": "porta-luvas",
        "industrial": "industrial",
        "medical": "médico",
        "military": "militar",
        "police": "polícia",
        "survivor": "sobrevivente",
        # vehicle types and groups (vehicle_types.lua)
        "boat": "barco",
        "car": "carro",
        "helicopter": "helicóptero",
        "motorbike": "mota",
        "plane": "avião",
        "pushbike": "bicicleta",
        "truck": "camião",
        "Civilian": "Civil",
        "Industrial": "Industrial",
        "Medical": "Médico",
        "Military": "Militar",
        "Police": "Polícia",
        "Unique": "Único",
    },
}
# fmt: on

# texts wiki_tables passes to t() through a variable rather than as a literal
DYNAMIC = [
    "Holster, on the back", "Holster, on the thigh",
    "civilian", "glovebox", "industrial", "medical", "military", "police", "survivor",
    "boat", "car", "helicopter", "motorbike", "plane", "pushbike", "truck",
    "Civilian", "Industrial", "Medical", "Military", "Police", "Unique",
]  # fmt: skip


def used_texts() -> set[str]:
    """Every English text wiki_tables translates: its t("...") literals, table headers, label tables and DYNAMIC."""
    src = (Path(__file__).parent / "wiki_tables.py").read_text(encoding="utf8")
    out = set(re.findall(r'\bt\("((?:[^"\\]|\\.)*)"\)', src)) | set(re.findall(r"\bt\('((?:[^'\\]|\\.)*)'\)", src))
    out = {s.replace('\\"', '"') for s in out}
    for m in re.finditer(r"md\(\[([^\]]*)\]", src):
        out |= {x for x in re.findall(r'"([^"]*)"', m.group(1)) if x}
    for name in ("CATEGORIES", "GROUPS", "CHARGES", "TRIGGERS", "SLOTS"):
        m = re.search(name + r" = \{(.*)\}", src)
        if m:
            out |= set(re.findall(r': "([^"]+)"', m.group(1)))
    return out | set(DYNAMIC)
