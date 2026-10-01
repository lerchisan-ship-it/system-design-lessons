# Benchmark PostgreSQL — контрольная точка на 10 000 пользователей

Дата фиксации: **1 октября 2026**

## 1. Размер тестового набора данных

| Таблица | Количество строк |
|---|---:|
| `users` | 10 000 |
| `profiles` | 10 000 |
| `cars` | 1 000 |
| `rentals` | 17 000 |
| `accidents` | 1 100 |

Для каждого benchmark-запроса использовался:

```sql
EXPLAIN (ANALYZE, BUFFERS)
```

Каждый запрос запускался минимум **3 раза**. Для тестов №6 и №7 было выполнено по 4 запуска; медиана для них рассчитана как среднее двух центральных значений.

---

# 2. Benchmark-запросы и результаты

## Тест 1. Поиск пользователя по email

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    u.user_id,
    u.email,
    p.full_name,
    p.driver_license
FROM users AS u
JOIN profiles AS p
    ON p.user_id = u.user_id
WHERE u.email = 'loadtest_user_0999@example.invalid';
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,069 мс |
| 2 | 0,043 мс |
| 3 | 0,039 мс |
| **Медиана** | **0,043 мс** |

---

## Тест 2. `COUNT(*)` по таблице `users`

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM users;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 4,264 мс |
| 2 | 0,546 мс |
| 3 | 0,490 мс |
| **Медиана** | **0,546 мс** |

Первый запуск заметно дороже двух последующих, поэтому для сравнения между масштабами используется медиана.

---

## Тест 3. История одного пользователя

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.rental_id,
    r.car_id,
    r.started_at,
    r.ended_at,
    r.rating_at_start,
    r.total_cost
FROM users AS u
JOIN profiles AS p
    ON p.user_id = u.user_id
JOIN rentals AS r
    ON r.profile_id = p.profile_id
WHERE u.email = 'loadtest_user_0999@example.invalid'
ORDER BY r.started_at;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 1,267 мс |
| 2 | 0,056 мс |
| 3 | 0,056 мс |
| **Медиана** | **0,056 мс** |

---

## Тест 4. История одной машины + ДТП

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.registration_number,
    r.rental_id,
    r.started_at,
    r.ended_at,
    a.accident_id,
    a.occurred_at,
    a.user_guilty
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
LEFT JOIN accidents AS a
    ON a.rental_id = r.rental_id
WHERE c.registration_number = 'LOADCAR-000001'
ORDER BY r.started_at;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 2,554 мс |
| 2 | 1,550 мс |
| 3 | 1,342 мс |
| **Медиана** | **1,550 мс** |

---

## Тест 5. Поиск аренд с `rating_at_start = 95`

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM rentals
WHERE rating_at_start = 95;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 1,209 мс |
| 2 | 0,731 мс |
| 3 | 0,928 мс |
| **Медиана** | **0,928 мс** |

---

## Тест 6. Топ аварийных машин

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.registration_number,
    COUNT(a.accident_id) AS accidents_count
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
JOIN accidents AS a
    ON a.rental_id = r.rental_id
GROUP BY
    c.car_id,
    c.registration_number
ORDER BY accidents_count DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 1,976 мс |
| 2 | 1,913 мс |
| 3 | 1,775 мс |
| 4 | 2,110 мс |
| **Медиана** | **1,945 мс** |

---

## Тест 7. Выручка по маркам автомобилей

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.brand,
    COUNT(r.rental_id) AS rentals_count,
    ROUND(SUM(r.total_cost), 2) AS total_revenue,
    ROUND(AVG(r.total_cost), 2) AS avg_rental_cost
FROM cars AS c
JOIN rentals AS r
    ON r.car_id = c.car_id
GROUP BY c.brand
ORDER BY total_revenue DESC;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 6,057 мс |
| 2 | 4,875 мс |
| 3 | 5,369 мс |
| 4 | 5,059 мс |
| **Медиана** | **5,214 мс** |

---

## Тест 8. Топ клиентов по количеству аренд и затратам

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    r.profile_id,
    COUNT(*) AS rentals_count,
    SUM(r.total_cost) AS total_spent
FROM rentals AS r
GROUP BY r.profile_id
ORDER BY
    rentals_count DESC,
    total_spent DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 6,792 мс |
| 2 | 6,412 мс |
| 3 | 7,142 мс |
| **Медиана** | **6,792 мс** |

---

## Тест 9. Фильтр по `started_at` без отдельного ведущего индекса

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM rentals
WHERE started_at >= TIMESTAMPTZ '2025-03-01 00:00:00+03'
  AND started_at <  TIMESTAMPTZ '2025-04-01 00:00:00+03';
```

Результаты базового benchmark:

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,860 мс |
| 2 | 0,877 мс |
| 3 | 0,840 мс |
| **Медиана** | **0,860 мс** |

---

## Тест 10. TOP-20 самых дорогих аренд

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    rental_id,
    profile_id,
    total_cost
FROM rentals
ORDER BY total_cost DESC
LIMIT 20;
```

Результаты:

| Запуск | Execution Time |
|---:|---:|
| 1 | 2,801 мс |
| 2 | 2,832 мс |
| 3 | 2,447 мс |
| **Медиана** | **2,801 мс** |

---

# 3. Итоговая таблица — 10 000 пользователей

| № | Тест | Медиана Execution Time |
|---:|---|---:|
| 1 | Пользователь по email | **0,043 мс** |
| 2 | `COUNT(*) users` | **0,546 мс** |
| 3 | История пользователя | **0,056 мс** |
| 4 | История машины + ДТП | **1,550 мс** |
| 5 | `rating_at_start = 95` | **0,928 мс** |
| 6 | Топ аварийных машин | **1,945 мс** |
| 7 | Выручка по маркам | **5,214 мс** |
| 8 | Топ клиентов по арендам | **6,792 мс** |
| 9 | Фильтр по `started_at` | **0,860 мс** |
| 10 | TOP-20 по `total_cost` | **2,801 мс** |

---

# 4. Сравнение с контрольной точкой 1k

| № | Тест | 1k | 10k | Рост |
|---:|---|---:|---:|---:|
| 1 | Пользователь по email | 0,033 мс | 0,043 мс | ×1,30 |
| 2 | `COUNT(*) users` | 0,106 мс | 0,546 мс | ×5,15 |
| 3 | История пользователя | 0,049 мс | 0,056 мс | ×1,14 |
| 4 | История машины + ДТП | 0,198 мс | 1,550 мс | ×7,83 |
| 5 | `rating_at_start = 95` | 0,115 мс | 0,928 мс | ×8,07 |
| 6 | Топ аварийных машин | 0,290 мс | 1,945 мс | ×6,71 |
| 7 | Выручка по маркам | 0,569 мс | 5,214 мс | ×9,16 |
| 8 | Топ клиентов по арендам | 0,682 мс | 6,792 мс | ×9,96 |
| 9 | Фильтр по `started_at` | 0,126 мс | 0,860 мс | ×6,83 |
| 10 | TOP-20 по `total_cost` | 0,280 мс | 2,801 мс | ×10,00 |

## Наблюдение

При десятикратном увеличении объёма данных точечные индексные запросы почти не изменились по времени. Массовые операции — полные просмотры, сортировки и агрегации — выросли значительно сильнее и в ряде случаев почти пропорционально размеру таблиц.

---

# 5. Отдельный эксперимент: индекс по `rentals.started_at`

Этот эксперимент **не входит в базовую серию benchmark**, потому что для сравнения 1k → 10k → 100k → 1M схема должна оставаться одинаковой.

### Без отдельного индекса

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM rentals
WHERE started_at >= TIMESTAMPTZ '2025-03-01 00:00:00+03'
  AND started_at <  TIMESTAMPTZ '2025-04-01 00:00:00+03';
```

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,937 мс |
| 2 | 0,799 мс |
| 3 | 0,850 мс |
| **Медиана** | **0,850 мс** |

План: `Seq Scan`.

### Создание временного экспериментального индекса

```sql
CREATE INDEX idx_test_rentals_started_at
ON rentals (started_at);

ANALYZE rentals;
```

### С индексом

| Запуск | Execution Time |
|---:|---:|
| 1 | 0,293 мс |
| 2 | 0,172 мс |
| 3 | 0,175 мс |
| **Медиана** | **0,175 мс** |

План изменился на:

```text
Index Only Scan using idx_test_rentals_started_at
Heap Fetches: 0
```

### Результат оптимизации

- без индекса: **0,850 мс**;
- с индексом: **0,175 мс**;
- ускорение: примерно **в 4,9 раза**;
- сокращение времени: примерно **на 79%**.

После эксперимента индекс был удалён, чтобы продолжить масштабный benchmark на исходной схеме:

```sql
DROP INDEX idx_test_rentals_started_at;
```

---

# 6. Краткий вывод по контрольной точке 10k

На масштабе 10 000 пользователей уже заметно различие между двумя классами запросов:

- точечный индексный поиск практически не чувствует десятикратного роста данных;
- последовательные просмотры, агрегирование и сортировка становятся ощутимо дороже;
- отдельный эксперимент с индексом по `started_at` подтвердил, что индекс, соответствующий реальному шаблону поиска, способен изменить план выполнения и дать существенное ускорение.

Следующая контрольная точка эксперимента — **100 000 пользователей**.
