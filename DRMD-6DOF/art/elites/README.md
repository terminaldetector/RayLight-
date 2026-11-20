# Элита Альянса · Half-Life: Abaddon

| Модель | Blender | GLB | Игровая команда |
|---|---|---|---|
| Ракетно-пулемётный бронедрон, средний класс | [citadel-enforcer.blend](citadel-enforcer.blend) | [citadel-enforcer.glb](citadel-enforcer.glb) | `6dof_spawn_heavy_elite` |
| Сверхтяжёлый дуговой штурмовик | [arc-elite.blend](arc-elite.blend) | [arc-elite.glb](arc-elite.glb) | `6dof_spawn_arc_elite` |

**Бронедрон.** Тёмная гранёная броня, утопленная красная линза дальномера, поисковая фара, две прямоугольные девятиячеечные кассеты и раздельные пулемётные группы. Лебёдка, трёхлапый крюк и ребристые магистрали образуют нижний силуэт.

**Дуговой штурмовик.** Синяя оптика в округлом корпусе, верхние плазморакеты и нижний рельсотрон. Круглые опоры удерживают подвижные боковые блоки и вращающиеся группы стволов. В игре поворот, отдача и точки вылета снарядов рассчитываются из одной позы. Оптика перед лучом меняет цвет на красный.

Файлы Blender 4.3 содержат отдельные сборки корпуса, оружия и навесных узлов, упакованные материалы и два ракурса в коллекции **Studio**. Ось +X направлена вперёд, +Z вверх. Пустышки `Socket · …` отмечают позиции визуальных эффектов и выходов оружия. GLB содержит модели и точки крепления.

Игровая геометрия хранится в [d6_art_elites.lua](../../descent_scanner/lua/d6_art_elites.lua). Из неё экспортируются и модели Source MDL в `descent_scanner/models/drmd/`, и сцены Blender. Оба дрона используют свои размеры на арене.

## Повторная сборка

Экспортируйте `art-models.json` командой `texlua export_art.lua` из каталога `tests`. Для генерации покрытий запустите `tools/build_elite_finishes.py` с каталогом VTF и каталогом текстур Blender. Для этого скрипта нужны NumPy и Pillow.

```bash
python tools/build_elite_finishes.py descent_scanner/materials/drmd textures
blender -b -P tools/build_elite_studio.py -- tests/art-models.json textures studio --render
```

Для игровой сборки используется [компилятор моделей](../../tools/compile_models.py). [Карты и сборка Source](../../MAPS_RU.md)
