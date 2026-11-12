import { PageContentState, PageScaffold } from './PageScaffold';

@Component
export struct PrimaryPlaceholder {
  @Prop eyebrow: ResourceStr;
  @Prop title: ResourceStr;
  @Prop description: ResourceStr;
  @Prop state: PageContentState = PageContentState.Empty;

  build() {
    PageScaffold({
      eyebrow: this.eyebrow,
      title: this.title,
      description: this.description,
      state: this.state
    })
  }
}
