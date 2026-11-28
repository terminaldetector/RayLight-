# Linux i386 с GCC 14

Облачная сборка использовала официальный SP SDK `77567eb4bce8d7b6b7f73e929fcde3a331c0216e`. Этот вариант рассчитан на GCC 14 и библиотеки i386. Поправки сохраняются отдельно от основного нативного оверлея.

- `clientmode-null-check.patch` заменяет сравнение указателя с целым числом штатной проверкой на NULL.
- `libm_finite.c` передаёт вызовы старых символов конечного ввода из статических библиотек SDK в стандартный libm.

Установите основной оверлей, сгенерируйте VPC-проекты, затем выполните следующие команды. В `ABADDON_CC` и `ABADDON_CXX` укажите абсолютные пути к компиляторам или обёрткам, которые по умолчанию используют sysroot i386 и `-m32`.

```sh
abaddon_src=/absolute/path/to/DRMD-6DOF/native/hl2
abaddon_sdk=/absolute/path/to/source-sdk-2013
abaddon_obj=/absolute/path/to/build-objects

mkdir -p "$abaddon_obj"
git -C "$abaddon_sdk" apply "$abaddon_src/linux_gcc14_compat/clientmode-null-check.patch"
"$ABADDON_CC" -fPIC -fno-builtin -fvisibility=hidden -O2 \
  -c "$abaddon_src/linux_gcc14_compat/libm_finite.c" -o "$abaddon_obj/libm_finite.o"

for side in client server; do
    destination="$abaddon_obj/$side"
    make -C "$abaddon_sdk/src/game/$side" -j2 -f "${side}_linux32_hl2.mak" \
      CFG=release CC="$ABADDON_CC" CXX="$ABADDON_CXX" OBJ_DIR="$destination" \
      'OptimizerLevel=-g0 -O0' GEN_SYM=true SystemLibraries="$abaddon_obj/libm_finite.o" \
      "$destination/$side.so"
    mkdir -p "$abaddon_sdk/game/mod_hl2/bin"
    strip -x -o "$abaddon_sdk/game/mod_hl2/bin/$side.so" "$destination/$side.so"
done
```

Для VPC нужен 32-битный интерпретатор. На облачном хосте VPC запущен из `src` командой `qemu-i386 -L /path/to/i386-sysroot ./devtools/bin/vpc_linux /linux32 /hl2 +gamedlls /mksln abaddon_hl2`.

Обе библиотеки, собранные в облаке, требуют i386 glibc 2.38 или новее. Сервер импортирует GLIBCXX_3.4.21, обе библиотеки — CXXABI_1.3.8. Для старой среды Steam нужен подходящий системный либо целевой Steam sysroot. Для целевой среды проверяется наличие версий символов перед запуском. [Журнал нативной сборки](../BUILD_RESULTS_RU.txt)
