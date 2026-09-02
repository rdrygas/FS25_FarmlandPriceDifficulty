# FS25 Farmland Price Difficulty

**Farmland Price Difficulty** to skryptowy mod do **Farming Simulator 25**, który uzależnia ceny zakupu gruntów od poziomu trudności ekonomicznej ustawionego w zapisie gry.

W grze bazowej cena gruntów nie zmienia się wraz z poziomem trudności ekonomicznej. Mod dodaje osobną tabelę mnożników przeznaczoną wyłącznie dla cen ziemi i nie modyfikuje `EconomyManager.COST_MULTIPLIER`, dzięki czemu pozostałe elementy ekonomii FS25 nadal korzystają ze standardowych zasad gry.

## Przyjęte założenia

Mod został przygotowany według następujących założeń:

- poziom **Normalny** powinien zachowywać standardową cenę gruntu wynikającą z mapy/gry;
- poziom **Łatwy** powinien umiarkowanie obniżać ceny ziemi, a nie radykalnie je zmniejszać;
- poziom **Trudny** powinien rzeczywiście podnosić ceny gruntów ponad wartość standardową;
- ceny gruntów powinny mieć własne mnożniki, niezależne od współczynników używanych przez FS25 dla innych kosztów gospodarki;
- zmiana poziomu trudności podczas rozgrywki powinna natychmiast przeliczać ceny gruntów;
- przy aktywnym **Precision Farming** cena tego samego gruntu powinna pozostawać stabilna i nie powinna zmieniać się tylko dlatego, że ponownie wywołano `Farmland:updatePrice()`.

Domyślny balans jest symetryczny względem poziomu Normalnego:

| Poziom ekonomiczny | Mnożnik | Różnica względem Normalnego |
|---|---:|---:|
| Łatwy | `0,75` | -25% |
| Normalny | `1,00` | bez zmian |
| Trudny | `1,25` | +25% |

## Sposób działania

Mod nadpisuje `Farmland:updatePrice()` zamiast zmieniać globalną tabelę `EconomyManager.COST_MULTIPLIER`.

Przy każdym przeliczeniu ceny gruntu mod:

1. pozwala grze bazowej, mapie oraz wcześniej zainstalowanym zgodnym mechanizmom wyliczyć cenę normalnym sposobem;
2. jeżeli aktywny jest Precision Farming, usuwa z **ceny zakupu gruntu** jego współczynnik `yieldPotential`;
3. traktuje uzyskaną wartość jako cenę odniesienia;
4. dokładnie jeden raz stosuje własny mnożnik poziomu trudności.

Końcowy wzór można zapisać jako:

```text
końcowa cena gruntu = cena odniesienia × mnożnik poziomu trudności
```

Ponieważ `superFunc()` przed zastosowaniem mnożnika ponownie wylicza cenę źródłową, kolejne odświeżenia ceny nie powodują kumulowania mnożnika 0,75 / 1,00 / 1,25.

### Przykład

Jeżeli standardowa cena gruntu na mapie wynosi **83 433 $/ha**:

| Poziom ekonomiczny | Obliczenie | Wynik |
|---|---:|---:|
| Łatwy | 83 433 × 0,75 | ~62 575 / ha |
| Normalny | 83 433 × 1,00 | ~83 433 / ha |
| Trudny | 83 433 × 1,25 | ~104 291 / ha |

## Zgodność z Precision Farming

Precision Farming może mnożyć cenę wyliczoną przez `Farmland:updatePrice()` przez wartość `yieldPotential` danego gruntu. Kolejność inicjalizacji tego mechanizmu powoduje, że bez dodatkowej obsługi wyświetlana cena ziemi może zależeć od tego, **kiedy** ponownie zostanie wywołane `updatePrice()`.

Podczas testów na mapie Riverbend Springs dla pola 24 występowały między innymi wartości:

```text
yieldPotential = 0,9665
standardowa cena = ~83 433 / ha
cena po ponownym przeliczeniu przez PF = ~80 638 / ha
```

Bez korekty zmiana poziomu trudności mogła więc powodować, że cena na poziomie Trudnym zmieniała się pomiędzy około **104 291/ha** i **100 798/ha**.

Aby temu zapobiec, mod usuwa współczynnik `yieldPotential` Precision Farming z ceny zakupu gruntu przed zastosowaniem własnego mnożnika trudności. Sam Precision Farming nadal działa; neutralizowany jest wyłącznie jego wpływ `yieldPotential` na **cenę zakupu ziemi**.

Za tę funkcję odpowiada ustawienie:

```lua
FarmlandPriceDifficulty.IGNORE_PF_YIELD_POTENTIAL_FOR_PRICE = true
```

Zalecane jest pozostawienie wartości `true`.

## Automatyczne przeliczanie cen

Ceny gruntów są przeliczane:

- jeden raz po pełnym wczytaniu kariery/zapisu gry;
- natychmiast po zmianie poziomu trudności ekonomicznej w ustawieniach gry.

Inicjalizacja jest celowo podpięta do `Mission00.loadMission00Finished`, dzięki czemu zapisany poziom trudności oraz mechanizmy Precision Farming są już dostępne, zanim mod zainstaluje swoją końcową warstwę obliczania ceny.

## Konfiguracja

Domyślne mnożniki znajdują się na początku pliku `FarmlandPriceDifficulty.lua`:

```lua
FarmlandPriceDifficulty.PRICE_MULTIPLIERS = {
    [1] = 0.75, -- Easy / Łatwy
    [2] = 1.00, -- Normal / Normalny
    [3] = 1.25  -- Hard / Trudny
}
```

Do zmiany balansu cen wystarczy zmodyfikować te trzy wartości. Na przykład:

```lua
FarmlandPriceDifficulty.PRICE_MULTIPLIERS = {
    [1] = 0.80,
    [2] = 1.00,
    [3] = 1.40
}
```

W takim wariancie poziom Łatwy obniży ceny o 20% względem Normalnego, a poziom Trudny podniesie je o 40%.

Zmiana dotyczy wyłącznie cen gruntów. Pozostałe koszty w grze nadal korzystają ze standardowych ustawień ekonomii FS25.

## Debugowanie

Szczegółowe logowanie diagnostyczne jest **domyślnie wyłączone**.

Można je włączyć lub wyłączyć poleceniem konsoli:

```text
fpdToggleDebug
```

Po włączeniu w `log.txt` pojawia się szczegółowy wpis dla każdego gruntu, zawierający między innymi:

- poziom trudności i użyty mnożnik;
- cenę zwróconą przez standardowy łańcuch obliczeń;
- odzyskaną cenę odniesienia;
- końcową cenę po zastosowaniu mnożnika;
- powierzchnię gruntu;
- cenę na hektar przed korektą, cenę odniesienia i cenę końcową;
- wartość `yieldPotential` Precision Farming;
- informację, czy współczynnik ceny Precision Farming został usunięty.

Tryb debug nie jest zapisywany i po każdym ponownym uruchomieniu gry zaczyna się jako wyłączony.

## Standardowe wpisy w logu

Podczas normalnej gry logowanie zostało celowo ograniczone. Typowe wpisy wyglądają następująco:

```text
Info: [FS25_FarmlandPriceDifficulty] Loaded: NORMAL x1.00, 93 farmlands refreshed.
Info: [FS25_FarmlandPriceDifficulty] Difficulty: HARD x1.25, 93 farmlands refreshed.
```

## Zakres działania i ograniczenia

- Farming Simulator 25.
- Mod jest przeznaczony i testowany do gry jednoosobowej; obsługa multiplayera jest wyłączona w `modDesc.xml`.
- Mod zmienia wyłącznie **ceny zakupu gruntów**.
- Precision Farming pozostaje w pełni aktywny, ale przy włączonej opcji zgodności jego `yieldPotential` jest celowo pomijany przy wyliczaniu ceny zakupu ziemi.
- Inny mod, który nadpisze cenę gruntów już po inicjalizacji tego moda, może nadal zmienić wynik końcowy.

## Historia zmian

### 1.0.0.0

- Pierwsze stabilne wydanie.
- Dodano niezależną tabelę mnożników cen gruntów:
  - Łatwy: 0,75;
  - Normalny: 1,00;
  - Trudny: 1,25.
- Poziom Normalny zachowuje standardową cenę odniesienia mapy/gry.
- Dodano automatyczne przeliczanie cen po wczytaniu kariery i po zmianie poziomu trudności ekonomicznej.
- Przeniesiono modyfikację ceny do `Farmland:updatePrice()`, aby mnożnik był stosowany do kompletnego wyniku obliczenia ceny gruntu.
- Dodano zgodność z Precision Farming przez usunięcie współczynnika `yieldPotential` z ceny zakupu ziemi przed zastosowaniem mnożnika trudności.
- Usunięto problem zmiany cen gruntów po wielokrotnym przełączaniu poziomu trudności przy aktywnym Precision Farming.
- Dodano opcjonalne polecenie diagnostyczne `fpdToggleDebug`.
- Debugowanie jest domyślnie wyłączone.
- Ograniczono standardowe wpisy w `log.txt` do krótkich komunikatów przy inicjalizacji i zmianie poziomu trudności.
