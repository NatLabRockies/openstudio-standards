module OpenStudioSimulation
  # Execution backends — the seam between "prepare a run directory" (the
  # backend-agnostic Runner) and "actually run EnergyPlus" (here).
  #
  # The Runner writes `dir/in.osm` + `dir/in.osw` into a run directory, then
  # hands that directory to a Backend. A backend's job is narrow and precise:
  # execute the simulation so that, on return, BOTH
  #   * `dir/run/eplusout.sql`  (results — parsed by Runner.energy_results)
  #   * `dir/run/eplusout.err`  (E+ log — parsed by Runner.clean_run?)
  # exist. On any failure the backend must raise.
  #
  # This is the local-vs-cloud seam: swap `Local` (the `openstudio` CLI on this
  # machine) for `Remote` (a remote/AWS EnergyPlus service) without the Runner,
  # the facade, or any consumer changing.
  class Backend
    # Execute the simulation for a prepared run directory.
    #
    # @param dir [String] a run directory already containing `in.osm` + `in.osw`
    # @return [void] — must leave `dir/run/eplusout.sql` and
    #   `dir/run/eplusout.err` in place; must raise on failure.
    def execute(_dir)
      raise(NotImplementedError, "#{self.class}#execute(dir) must run EnergyPlus and " \
                                 'produce dir/run/eplusout.sql + dir/run/eplusout.err')
    end
  end

  # Local execution via the `openstudio` CLI on this machine — exactly the
  # command the runner has always used. This is the default backend.
  class Local < Backend
    # @return [Boolean] is the `openstudio` CLI on PATH?
    def openstudio_cli?
      @openstudio_cli = system('openstudio openstudio_version > /dev/null 2>&1') if @openstudio_cli.nil?
      @openstudio_cli
    end

    def execute(dir)
      raise('openstudio CLI not available on PATH') unless openstudio_cli?

      ok = system("openstudio run -w #{dir}/in.osw > #{dir}/cli.log 2>&1")
      err_path = "#{dir}/run/eplusout.err"
      raise("EnergyPlus run failed in #{dir} and wrote no eplusout.err — see #{dir}/cli.log") unless File.exist?(err_path)
      return nil if ok

      # The Fatal line is usually the useless 'final processing' one — the
      # SEVERE lines above it carry the cause. Surface both, plus the path.
      err = File.read(err_path)
      severes = err.scan(/^\s*\*\* Severe {2}\*\*.*(?:\n\s*\*\* {3}~~~ {3}\*\*.*)*/)
      fatal = err[/^.*Fatal.*$/]
      detail = (severes.first(5) + [fatal]).compact.join("\n").strip
      detail = err[-800..] || err if detail.empty?
      raise("EnergyPlus run failed in #{dir}:\n#{detail}\n(full log: #{err_path})")
    end
  end

  # Remote/cloud execution — a DOCUMENTED STUB awaiting a real endpoint spec.
  #
  # This is the intended extension point for running EnergyPlus against a
  # provided remote service (e.g. an AWS API) instead of the local CLI. The
  # contract is identical to every other backend: given a `dir` that already
  # contains `in.osm` + `in.osw`, run the simulation remotely and land
  # `dir/run/eplusout.sql` and `dir/run/eplusout.err` back on the local disk.
  #
  # The skeleton below is modelled on a REAL service observed this session — an
  # AWS-Batch EnergyPlus/OpenStudio runner (the "hbix" simulation API, region
  # ca-central-1) whose flow is:
  #
  #   upload_model(filename)      -> { model_id, upload_url (presigned S3 PUT), s3_key }
  #   PUT the model bytes to upload_url                       (direct to S3)
  #   submit_simulation(model_id, weather_station_id,         -> { job_id, status, phases }
  #                     weather_format, workflow_type,
  #                     engine_version, queue)
  #   get_simulation_status(job_id) / get_simulation_progress(job_id)
  #                                                           (poll: pending|running|failed|completed)
  #   get_simulation_results(job_id)                          -> presigned download URLs (~15 min TTL)
  #
  # HARD-WON NOTES from validating that service live:
  #   * ENGINE VERSION MUST MATCH THE MODEL. Neither OpenStudio nor EnergyPlus
  #     translates *backward*. A model saved by OpenStudio 3.11 / EnergyPlus 25.2
  #     fails instantly ("Essential container exited (exit code 1)") on the
  #     platform-default OpenStudio 3.9 runner. Submit an IDF/OSM whose version
  #     an available remote engine can open — pass `engine_version:` explicitly
  #     (e.g. '25.2') rather than relying on the platform "latest" default.
  #   * The `openstudio` workflow is 2-phase (measures 3.x -> energyplus 24/25.x);
  #     the `energyplus` workflow is 1-phase and takes a translated IDF directly.
  #   * The service is async on AWS Batch — expect a cold-start before the phase
  #     leaves `submitted`; poll on a backoff, don't tight-loop.
  #
  # We deliberately do NOT ship a working client: the MCP that surfaced this API
  # is agent-facing, so the raw REST endpoints + auth headers behind it are not
  # ours to hardcode. Supply `endpoint:`/`api_key:` for the service's HTTP API
  # and fill in the transport.
  class Remote < Backend
    # @param endpoint [String, nil] base URL of the remote simulation service
    # @param api_key [String, nil] credential for the service
    # @param opts [Hash] transport options — e.g. weather_station_id:,
    #   weather_format:, workflow_type: ('energyplus'|'openstudio'),
    #   engine_version: (MUST match the model — see class notes), queue:,
    #   poll_seconds:, region:
    def initialize(endpoint: nil, api_key: nil, **opts)
      super()
      @endpoint = endpoint
      @api_key = api_key
      @opts = opts
    end

    def execute(_dir)
      raise(NotImplementedError, <<~MSG)
        OpenStudioSimulation::Remote is a documented stub — no remote endpoint is wired yet.

        To implement, `execute(dir)` must, using @endpoint / @api_key / @opts:
          1. UPLOAD  dir/in.osm (or a translated dir/run/in.idf for the energyplus
                     workflow) to the service, then PUT the bytes to the presigned
                     upload_url it returns.
          2. SUBMIT  a run for the uploaded model_id, passing an engine_version
                     that MATCHES the model (backward translation does not exist).
          3. POLL    status/progress to a terminal state (completed | failed).
          4. DOWNLOAD the result bundle's eplusout.sql + eplusout.err into dir/run/.
          5. RAISE   if the remote run failed or the artifacts are missing —
             same contract as Backend#execute / Local#execute.

        Once dir/run/eplusout.sql + dir/run/eplusout.err exist locally, the rest
        of the pipeline (Runner.clean_run?, energy_results, unmet_occupied_hours)
        is transport-agnostic and works unchanged.
      MSG

      # --- SKELETON modelled on the observed AWS-Batch service (shape only) --
      # require 'net/http'; require 'json'; require 'uri'
      # FileUtils.mkdir_p("#{dir}/run")
      #
      # # 1. register the model, then PUT bytes straight to the presigned S3 URL
      # up = post_json("#{@endpoint}/models", { filename: 'in.osm' })   # -> model_id, upload_url, s3_key
      # put_bytes(up['upload_url'], File.binread("#{dir}/in.osm"))       # HTTP 200 from S3
      #
      # # 2. submit — engine_version MUST match the model's version
      # job = post_json("#{@endpoint}/simulations", {
      #   model_id:           up['model_id'],
      #   weather_station_id: @opts[:weather_station_id],
      #   weather_format:     @opts[:weather_format],
      #   workflow_type:      @opts.fetch(:workflow_type, 'openstudio'),
      #   engine_version:     @opts[:engine_version],
      #   queue:              @opts.fetch(:queue, 'auto'),
      # })                                                              # -> { job_id, status }
      #
      # # 3. poll to terminal state (async on AWS Batch — expect a cold start)
      # loop do
      #   st = get_json("#{@endpoint}/simulations/#{job['job_id']}")    # pending|running|failed|completed
      #   raise("remote run failed: #{st['phases']&.map { |p| p['errors'] }}") if st['status'] == 'failed'
      #   break if st['status'] == 'completed'
      #   sleep(@opts.fetch(:poll_seconds, 15))
      # end
      #
      # # 4. fetch presigned result URLs (short TTL) and pull the two artifacts
      # res = get_json("#{@endpoint}/simulations/#{job['job_id']}/results")
      # File.binwrite("#{dir}/run/eplusout.sql", get_bytes(res.dig('files', 'eplusout.sql')))
      # File.binwrite("#{dir}/run/eplusout.err", get_bytes(res.dig('files', 'eplusout.err')))
      #
      # # 5. fail loudly if artifacts are missing
      # raise("remote run produced no eplusout.sql") unless File.exist?("#{dir}/run/eplusout.sql")
      # ----------------------------------------------------------------------
    end
  end
end
