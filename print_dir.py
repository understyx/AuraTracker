import os


IGNORE_DIRS = {".git", "Media", "Libraries", "Unitframes", "Editmode", "Swingbar"}
IGNORE_FILES = {
    "print_dir.py",
    "SpellDatabase.lua",
    "combined_output.txt",
    'Helpers.lua',
    'CooldownManager.lua'
}


def write_file_tree(base_dir, outfile):
    outfile.write("===== FILE TREE =====\n")

    for root, dirs, files in os.walk(base_dir):
        if ".git" in dirs:
            dirs.remove(".git")

        level = os.path.relpath(root, base_dir).count(os.sep)
        indent = "    " * level
        dir_name = os.path.basename(root) or base_dir

        outfile.write(f"{indent}[DIR] {dir_name}\n")

        for d in dirs:
            if d in IGNORE_DIRS:
                outfile.write(f"{indent}    [IGNORED DIR] {d}\n")

        for f in files:
            if f == ".gitignore":
                continue

            label = (
                "IGNORED FILE" if f in IGNORE_FILES else "FILE"
            )
            outfile.write(f"{indent}    [{label}] {f}\n")

    outfile.write("\n\n")


def aggregate_files(target_directory, output_file_path):
    with open(output_file_path, "w", encoding="utf-8") as outfile:
        #write_file_tree(target_directory, outfile)

        #outfile.write("===== FILE CONTENTS =====\n\n")

        for root, dirs, files in os.walk(target_directory):
            # Prevent descending into ignored dirs
            dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]

            for file in files:
                if file in IGNORE_FILES or file == ".gitignore":
                    continue

                file_path = os.path.join(root, file)

                if os.path.abspath(file_path) == os.path.abspath(
                    output_file_path
                ):
                    continue

                outfile.write(f"FILE: {file_path}\n")

                try:
                    with open(
                        file_path,
                        "r",
                        encoding="utf-8",
                        errors="ignore",
                    ) as infile:
                        outfile.write(infile.read())
                except Exception as e:
                    outfile.write(f"Could not read file: {e}")

                outfile.write("\n\n")


if __name__ == "__main__":
    current_dir = os.path.dirname(os.path.realpath(__file__))
    working_dir = os.getcwd()
    output_name = "combined_output.txt"
    output_path = os.path.join(working_dir, output_name)

    aggregate_files(working_dir, output_path)
    print(f"Done! Contents written to {output_name}")