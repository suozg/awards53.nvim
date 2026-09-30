#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time

uno_paths = [
    "/usr/lib/python3/dist-packages",
    "/usr/lib64/python3/site-packages",
    "/usr/lib/libreoffice/program",
]
for p in uno_paths:
    if os.path.exists(p) and p not in sys.path:
        sys.path.append(p)

try:
    import uno
    from com.sun.star.beans import PropertyValue
except ImportError:
    sys.stderr.write("Помилка: Модуль 'uno' не знайдено.\n")
    sys.exit(1)


def prop(name, value):
    p = PropertyValue()
    p.Name = name
    p.Value = value
    return p


def get_desktop_via_pipe():
    pipe_name = "doc53_uno_pipe"
    connection_str = f"uno:pipe,name={pipe_name};urp;StarOffice.ComponentContext"

    local_context = uno.getComponentContext()
    resolver = local_context.ServiceManager.createInstanceWithContext(
        "com.sun.star.bridge.UnoUrlResolver", local_context
    )

    user_profile = "/tmp/doc53_lo_profile"
    os.makedirs(user_profile, exist_ok=True)

    cmd = [
        "soffice",
        "--headless",
        "--invisible",
        "--nocrashreport",
        "--nodefault",
        "--nofirststartwizard",
        "--nolockcheck",
        "--nologo",
        f"-env:UserInstallation=file://{user_profile}",
        f"--accept=pipe,name={pipe_name};urp;StarOffice.ComponentContext",
    ]

    process = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

    for _ in range(50):
        try:
            ctx = resolver.resolve(connection_str)
            desktop = ctx.ServiceManager.createInstanceWithContext(
                "com.sun.star.frame.Desktop", ctx
            )
            return desktop, process
        except Exception:
            time.sleep(0.2)

    process.terminate()
    raise RuntimeError("Не вдалося запустити LibreOffice через Pipe")


def insert_formatted_text(text_obj, cursor, text):
    raw_str = str(text)
    # Превращаем экранированные строки из JSON обратно в спецсимволы
    raw_str = raw_str.replace("\\t", "\t").replace("\\n", "\n")

    # В UNO API PARAGRAPH_BREAK имеет значение 0
    PARAGRAPH = 0

    lines = raw_str.split("\n")

    for row_idx, line in enumerate(lines):
        # insertString автоматически вставляет и корректно обрабатывает символ \t
        text_obj.insertString(cursor, line, False)

        # Вставляем абзац для всех строк, кроме последней
        if row_idx < len(lines) - 1:
            text_obj.insertControlCharacter(
                cursor, PARAGRAPH, False
            )


def process_single_document(
    desktop, tpl_path, output_path, fields, table_data=None
):
    url = uno.systemPathToFileUrl(os.path.abspath(tpl_path))
    doc = desktop.loadComponentFromURL(
        url, "_blank", 0, (prop("Hidden", True), prop("ReadOnly", False))
    )

    if isinstance(fields, list):
        fields = {}

    try:
        bookmarks = doc.getBookmarks()
        bookmark_names = bookmarks.getElementNames()  # Получаем список всех закладок в документе

        # 1. ЗАПОВНЕННЯ ЗАКЛАДОК (ПОЛЯ)
        for name, value in fields.items():
            # Пропускаем специальную закладку таблицы
            if name == "TABLE_DATA" or value is None:
                continue

            # Проверяем абсолютно все закладки в документе
            for bm_name in bookmark_names:
                # Если название закладки совпадает с именем поля (FIELD1)
                # ИЛИ начинается с него с подчеркиванием (FIELD1_1, FIELD1_2, FIELD1_копия и т.д.)
                if bm_name == name or bm_name.startswith(f"{name}_"):
                    bookmark = bookmarks.getByName(bm_name)
                    anchor = bookmark.getAnchor()
                    text_obj = anchor.getText()

                    cursor = text_obj.createTextCursorByRange(anchor)
                    cursor.gotoRange(anchor.getEnd(), True)
                    cursor.setString("")  # Очищаем старый текст

                    insert_formatted_text(text_obj, cursor, str(value))

        # 2. ЗАПОВНЕННЯ ТАБЛИЦІ (AWARDS53)
        if table_data and len(table_data) > 0:
            if bookmarks.hasByName("TABLE_DATA"):
                bookmark = bookmarks.getByName("TABLE_DATA")
                anchor = bookmark.getAnchor()
                
                # Отримуємо об'єкт таблиці, в якій лежить закладка TABLE_DATA
                table = anchor.TextTable

                if table is not None:
                    template_cols_count = table.getColumns().getCount()
                    incoming_cols_count = len(table_data[0])

                    if template_cols_count != incoming_cols_count:
                        sys.stderr.write(
                            f"Невідповідність структури таблиці!\n"
                            f"У даних: {incoming_cols_count} колон(ок), у шаблоні ODT: {template_cols_count} колон(ок).\n"
                        )
                        sys.exit(1)

                    rows = table.getRows()
                    
                    # Заповнюємо рядки
                    for row_idx, row_data in enumerate(table_data):
                        # Додаємо новий рядок в таблицю LibreOffice для кожного запису (крім першого рядочка-шаблону)
                        if row_idx > 0:
                            rows.insertByIndex(rows.getCount(), 1)

                        current_row_idx = rows.getCount() - 1

                        for col_idx, cell_value in enumerate(row_data):
                            cell = table.getCellByPosition(col_idx, current_row_idx)
                            # Вставляємо текст у комірку із підтримкою табуляції та нових рядків
                            cell_text = cell.getText()
                            cell.setString("") # Очищаємо комірку
                            cursor = cell_text.createTextCursor()
                            insert_formatted_text(cell_text, cursor, str(cell_value))

        out_url = uno.systemPathToFileUrl(os.path.abspath(output_path))
        doc.storeAsURL(out_url, (prop("FilterName", "writer8"),))
    finally:
        doc.close(True)


def main():
    if len(sys.argv) < 2:
        return

    payload_raw = sys.argv[1]
    payload = json.loads(payload_raw)

    desktop, lo_process = get_desktop_via_pipe()

    try:
        for task in payload.get("tasks", []):
            process_single_document(
                desktop,
                task["template"],
                task["output"],
                task.get("fields", {}),
                task.get("table_data", None),
            )
    except Exception as e:
        sys.stderr.write(f"Помилка: {str(e)}\n")
        sys.exit(1)
    finally:
        lo_process.terminate()
        try:
            lo_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            lo_process.kill()
            lo_process.wait()


if __name__ == "__main__":
    main()
