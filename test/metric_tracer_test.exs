defmodule MetricTracerTest do
  use ExUnit.Case

  alias NewRelic.Harvest.Collector

  setup do
    TestHelper.restart_harvest_cycle(Collector.Metric.HarvestCycle)
    on_exit(fn -> TestHelper.pause_harvest_cycle(Collector.Metric.HarvestCycle) end)
  end

  defmodule MetricTraced do
    use NewRelic.Tracer

    @trace :fun
    def fun do
    end

    @trace :bar
    def foo do
    end

    @trace {:query, category: :external}
    def query do
    end

    @trace {:query, category: :external}
    def distributed_query do
      NewRelic.set_span(:http, url: "domain.net", method: "GET", component: "MetricTraced")
    end

    @trace {:db_query, category: :datastore}
    def db_query do
    end

    @trace {:special, category: :external}
    def custom_name do
    end
  end

  test "External metrics" do
    MetricTraced.query()
    MetricTraced.query()
    MetricTraced.custom_name()
    MetricTraced.custom_name()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/MetricTracerTest.MetricTraced.query/all", 2)

    assert TestHelper.find_metric(
             metrics,
             "External/MetricTracerTest.MetricTraced.custom_name:special/all",
             2
           )
  end

  test "External metrics use span data" do
    MetricTraced.distributed_query()
    MetricTraced.distributed_query()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(metrics, "External/domain.net/MetricTraced/GET/all", 2)
  end

  test "Datastore metrics" do
    MetricTraced.db_query()

    metrics = TestHelper.gather_harvest(Collector.Metric.Harvester)

    assert TestHelper.find_metric(
             metrics,
             "Datastore/statement/Database/MetricTracerTest.MetricTraced/db_query"
           )

    assert TestHelper.find_metric(metrics, "Datastore/Database/all")
  end
end
