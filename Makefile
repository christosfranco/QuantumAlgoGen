

build-dev:
	docker compose build quantumsafe


dev: build-dev
	docker compose run --use-aliases --rm quantumsafe



fips-build-dev:
	docker compose build fips_quantumsafe


fips-dev: fips-build-dev
	docker compose run --use-aliases --rm fips_quantumsafe