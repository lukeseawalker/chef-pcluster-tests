#!/usr/bin/env python

import argparse
from jinja2 import Environment, FileSystemLoader

CONFIG_DIR = 'configs'
TEMPLATE_FILENAME = 'config.j2'

def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--version', required=True)
    p.add_argument('--region', required=True)
    p.add_argument('--os', required=True)
    return p.parse_args()


def make_config_file(config_args):
    file_loader = FileSystemLoader(CONFIG_DIR)
    env = Environment(loader=file_loader)
    return env.get_template(TEMPLATE_FILENAME).render(**vars(config_args))


def main():
    args = parse_args()
    config_text = make_config_file(args)
    output_config_file = f"{CONFIG_DIR}/{args.version}-{args.region}-{args.os}.config"
    with open(output_config_file, 'w') as outfile:
        outfile.write(config_text)
    print(output_config_file)


if __name__ == "__main__":
    main()
