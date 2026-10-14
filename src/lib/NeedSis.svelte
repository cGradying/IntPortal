<script lang="ts">
  // For a student with eMabini but no SIS login: what this screen needs, and
  // where to add it.
  import LarNote from "./LarNote.svelte";
  import { app } from "./state.svelte";

  let { what }: { what: string } = $props();
</script>

<LarNote mood="open">
  Add your SIS login to see {what}.
  <button onclick={() => (app.tab = "you")}>Add SIS login</button>
</LarNote>

<style>
  button {
    display: block;
    margin-top: 10px;
    height: 36px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
  }
</style>
